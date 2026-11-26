// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import MapLibre
import SwiftUI

/// Karte einer Verbindung: Streckenverlauf in Linienfarben, Halte, Umstiege, eigener Standort und
/// Fahrzeugposition – in Dresden live aus TLMS, sonst geschätzt.
/// Kartendarstellung: MapLibre (Open Source), Kartendaten: OpenFreeMap/OpenStreetMap.
struct TripMapView: View {
    let trip: Trip
    /// Ganzer Lauf je Fahrt (Index in `trip.legs`), falls bekannt – dann ist auch die anrollende Bahn zu sehen.
    var runs: [Int: TripLeg] = [:]

    private var feed: LiveVehicleFeed { .shared }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// Die Kartenkacheln ließen sich nicht laden (meist: kein Netz).
    @State private var mapFailed = false

    var body: some View {
        ZStack(alignment: .top) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                TripMapRepresentable(trip: trip, now: context.date, dark: colorScheme == .dark,
                                     live: liveStates(at: context.date), onFailure: { mapFailed = true })
                    .ignoresSafeArea()
            }

            if mapFailed {
                ContentUnavailableView("Karte nicht geladen", systemImage: "wifi.exclamationmark",
                                       description: Text("Die Kartendaten sind gerade nicht erreichbar. Prüfe deine Internetverbindung."))
                    .background(.regularMaterial)
                    .ignoresSafeArea()
            }

            HStack(alignment: .top) {
                legend
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Karte schließen")
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomLeading) {
            attribution
        }
        // TLMS nur abfragen, wenn eine Fahrt der Verbindung überhaupt im Feed vorkommen kann.
        .task { if trip.mayHaveLiveVehicles { await feed.keepUpdated() } }
    }

    /// Live-Zustand je Fahrt (Index in `trip.legs`), soweit TLMS ein passendes Fahrzeug meldet.
    private func liveStates(at now: Date) -> [Int: LiveRideState] {
        var states: [Int: LiveRideState] = [:]
        for (index, leg) in trip.legs.enumerated() where leg.kind == .ride {
            states[index] = feed.state(for: leg, run: runs[index], at: now)
        }
        return states
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(trip.departure.scheduledTime.formatted(date: .omitted, time: .shortened)) → \(trip.arrival.scheduledTime.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            HStack(spacing: 4) {
                ForEach(Array(trip.rides.enumerated()), id: \.offset) { index, ride in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    LineBadge(line: ride.line ?? "?", mode: ride.mode ?? .other, compact: true)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Pflicht-Quellenangabe von OpenFreeMap / OpenMapTiles / OpenStreetMap.
    private var attribution: some View {
        HStack(spacing: 4) {
            Link("OpenFreeMap", destination: URL(string: "https://openfreemap.org")!)
            Link("© OpenMapTiles", destination: URL(string: "https://www.openmaptiles.org/")!)
            Link("© OpenStreetMap", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            if trip.mayHaveLiveVehicles, !feed.vehicles.isEmpty {
                Link("Live: TLMS", destination: URL(string: "https://tlm.solutions")!)
            }
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .padding(.leading, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - MapLibre-Anbindung

private struct TripMapRepresentable: UIViewRepresentable {
    let trip: Trip
    let now: Date
    let dark: Bool
    let live: [Int: LiveRideState]
    var onFailure: () -> Void = {}

    static func styleURL(dark: Bool) -> URL {
        URL(string: "https://tiles.openfreemap.org/styles/\(dark ? "dark" : "positron")")!
    }

    func makeCoordinator() -> Coordinator { Coordinator(trip: trip) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: Self.styleURL(dark: dark))
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.compassViewPosition = .bottomRight
        map.logoView.isHidden = false
        map.attributionButtonPosition = .bottomRight
        context.coordinator.dark = dark
        // Kamera erst setzen, wenn die Karte ihre Größe kennt (siehe didFinishLoading).
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.dark != dark {
            coordinator.dark = dark
            map.styleURL = Self.styleURL(dark: dark)
        }
        // Nachgeladene Echtzeitdaten übernehmen – sonst rechnet die geschätzte Position mit dem alten Stand.
        coordinator.trip = trip
        coordinator.onFailure = onFailure
        coordinator.live = live
        coordinator.updateVehicles(on: map, now: now)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var trip: Trip
        var onFailure: () -> Void = {}
        var dark = false
        var live: [Int: LiveRideState] = [:]
        /// Ein Fahrzeug-Marker pro gerade befahrenem Abschnitt.
        private var vehicles: [Int: VehicleAnnotation] = [:]
        private var didFitCamera = false

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            guard !didFitCamera, mapView.bounds.width > 0 else { return }
            didFitCamera = true
            fitCamera(on: mapView, animated: false)
        }

        init(trip: Trip) { self.trip = trip }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: any Error) {
            onFailure()
        }

        func fitCamera(on map: MLNMapView, animated: Bool) {
            var coordinates = trip.legs.flatMap(\.drawablePath).map(\.clCoordinate)
            coordinates += trip.legs.flatMap(\.stops).compactMap(\.coordinate).map(\.clCoordinate)
            guard !coordinates.isEmpty else { return }
            map.setVisibleCoordinates(&coordinates, count: UInt(coordinates.count),
                                      // Seitlich Platz für die Haltestellennamen lassen.
                                      edgePadding: UIEdgeInsets(top: 150, left: 110, bottom: 90, right: 110),
                                      animated: animated)
        }

        // Linien und Halte als Stil-Ebenen (unterstützen Farben, Umrandung und gestrichelte Fußwege).
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            for (index, leg) in trip.legs.enumerated() {
                var coordinates = leg.drawablePath.map(\.clCoordinate)
                guard coordinates.count >= 2 else { continue }
                let line = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
                let source = MLNShapeSource(identifier: "leg-\(index)", shape: line, options: nil)
                style.addSource(source)

                if leg.kind == .walk {
                    let layer = MLNLineStyleLayer(identifier: "leg-\(index)-line", source: source)
                    layer.lineColor = NSExpression(forConstantValue: UIColor.systemGray)
                    layer.lineWidth = NSExpression(forConstantValue: 3)
                    layer.lineDashPattern = NSExpression(forConstantValue: [1.5, 1.5])
                    layer.lineCap = NSExpression(forConstantValue: "round")
                    style.addLayer(layer)
                } else {
                    let casing = MLNLineStyleLayer(identifier: "leg-\(index)-casing", source: source)
                    casing.lineColor = NSExpression(forConstantValue: dark ? UIColor.black : UIColor.white)
                    casing.lineWidth = NSExpression(forConstantValue: 9)
                    casing.lineCap = NSExpression(forConstantValue: "round")
                    casing.lineJoin = NSExpression(forConstantValue: "round")
                    style.addLayer(casing)

                    let layer = MLNLineStyleLayer(identifier: "leg-\(index)-line", source: source)
                    layer.lineColor = NSExpression(forConstantValue: UIColor((leg.mode ?? .other).color))
                    layer.lineWidth = NSExpression(forConstantValue: 5)
                    layer.lineCap = NSExpression(forConstantValue: "round")
                    layer.lineJoin = NSExpression(forConstantValue: "round")
                    style.addLayer(layer)
                }
            }

            addStops(to: style)
            updateVehicles(on: mapView, now: .now)
            if !didFitCamera, mapView.bounds.width > 0 {
                didFitCamera = true
                fitCamera(on: mapView, animated: false)
            }
        }

        private func addStops(to style: MLNStyle) {
            var minor: [MLNPointFeature] = []
            var major: [MLNPointFeature] = []
            for leg in trip.rides {
                for (index, stop) in leg.stops.enumerated() {
                    guard let coordinate = stop.coordinate else { continue }
                    let feature = MLNPointFeature()
                    feature.coordinate = coordinate.clCoordinate
                    feature.attributes = ["name": stop.name]
                    if index == 0 || index == leg.stops.count - 1 { major.append(feature) } else { minor.append(feature) }
                }
            }

            let background = dark ? UIColor.black : UIColor.white
            let minorSource = MLNShapeSource(identifier: "stops-minor", features: minor, options: nil)
            style.addSource(minorSource)
            let minorLayer = MLNCircleStyleLayer(identifier: "stops-minor", source: minorSource)
            minorLayer.circleRadius = NSExpression(forConstantValue: 3.5)
            minorLayer.circleColor = NSExpression(forConstantValue: background)
            minorLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.darkGray)
            minorLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            style.addLayer(minorLayer)

            // Ein-, Um- und Ausstieg größer und beschriftet.
            let majorSource = MLNShapeSource(identifier: "stops-major", features: major, options: nil)
            style.addSource(majorSource)
            let majorLayer = MLNCircleStyleLayer(identifier: "stops-major", source: majorSource)
            majorLayer.circleRadius = NSExpression(forConstantValue: 7)
            majorLayer.circleColor = NSExpression(forConstantValue: background)
            majorLayer.circleStrokeColor = NSExpression(forConstantValue: dark ? UIColor.white : UIColor.black)
            majorLayer.circleStrokeWidth = NSExpression(forConstantValue: 3)
            style.addLayer(majorLayer)

            let labels = MLNSymbolStyleLayer(identifier: "stops-major-labels", source: majorSource)
            labels.text = NSExpression(forKeyPath: "name")
            // Muss eine Schrift des OpenFreeMap-Servers sein – die MapLibre-Standardschrift (Open Sans) gibt es
            // dort nicht, und solange sie fehlt, zeichnet MapLibre auch die Kreise dieser Quelle nicht.
            labels.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            labels.textFontSize = NSExpression(forConstantValue: 13)
            labels.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.4)))
            labels.textAnchor = NSExpression(forConstantValue: "top")
            labels.textColor = NSExpression(forConstantValue: dark ? UIColor.white : UIColor.black)
            labels.textHaloColor = NSExpression(forConstantValue: background)
            labels.textHaloWidth = NSExpression(forConstantValue: 1.5)
            style.addLayer(labels)
        }

        /// Fahrzeugposition(en) setzen oder entfernen: live aus TLMS, wenn ein passendes Fahrzeug gemeldet ist,
        /// sonst geschätzt anhand von Fahrplan/Echtzeit.
        func updateVehicles(on map: MLNMapView, now: Date) {
            for (index, leg) in trip.legs.enumerated() where leg.kind == .ride {
                let live = self.live[index]
                let position = live?.position ?? leg.estimatedPosition(at: now)

                // Wechsel zwischen live und geschätzt: Marker neu anlegen (anderes Aussehen).
                if let existing = vehicles[index], existing.isLive != (live != nil) {
                    map.removeAnnotation(existing)
                    vehicles[index] = nil
                }

                if let position {
                    if let existing = vehicles[index] {
                        existing.update(live: live, now: now)
                        // Ein Schritt pro Sekunde, linear über eine Sekunde ausgeführt → gleichmäßige Fahrt statt Sprünge.
                        UIView.animate(withDuration: 1, delay: 0,
                                       options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
                            existing.coordinate = position.clCoordinate
                        }
                    } else {
                        let annotation = VehicleAnnotation(leg: leg, isLive: live != nil)
                        annotation.update(live: live, now: now)
                        annotation.coordinate = position.clCoordinate
                        vehicles[index] = annotation
                        map.addAnnotation(annotation)
                    }
                } else if let existing = vehicles.removeValue(forKey: index) {
                    map.removeAnnotation(existing)
                }
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let vehicle = annotation as? VehicleAnnotation else { return nil }
            let id = "vehicle-\(vehicle.leg.mode?.rawValue ?? "other")-\(vehicle.isLive ? "live" : "estimated")"
            if let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) { return view }
            return VehicleAnnotationView(reuseIdentifier: id, mode: vehicle.leg.mode ?? .other, isLive: vehicle.isLive)
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            annotation is VehicleAnnotation
        }
    }
}

/// Position eines Fahrzeugs: live (TLMS-Meldung, bis zum nächsten Halt weitergerückt) oder geschätzt
/// (aus Fahrplan/Echtzeit interpoliert). Beides ist kein GPS des Fahrzeugs.
private final class VehicleAnnotation: MLNPointAnnotation {
    let leg: TripLeg
    let isLive: Bool

    init(leg: TripLeg, isLive: Bool) {
        self.leg = leg
        self.isLive = isLive
        super.init()
        title = "\(leg.line ?? "") \(leg.direction.map { "→ \($0)" } ?? "")"
        subtitle = "Geschätzte Position"
    }

    func update(live: LiveRideState?, now: Date) {
        guard let live else { return }
        let seconds = max(0, Int(now.timeIntervalSince(live.vehicle.reportedAt)))
        let age = seconds < 60 ? "vor \(seconds) s" : "vor \(seconds / 60) min"
        var text = "Live-Position (TLMS), gemeldet \(age)"
        if let away = live.stopsAway { text += " · \(LiveText.approaching(stopsAway: away))" }
        if subtitle != text { subtitle = text }
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }
}

private final class VehicleAnnotationView: MLNAnnotationView {
    init(reuseIdentifier: String, mode: TransportMode, isLive: Bool) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        let circle = UIView(frame: bounds)
        circle.backgroundColor = UIColor(mode.color)
        circle.layer.cornerRadius = 17
        circle.layer.borderColor = UIColor.white.cgColor
        circle.layer.borderWidth = 3
        circle.layer.shadowColor = UIColor.black.cgColor
        circle.layer.shadowOpacity = 0.3
        circle.layer.shadowRadius = 3
        circle.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(circle)

        let icon = UIImageView(image: UIImage(systemName: mode.symbolName,
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.frame = bounds
        addSubview(icon)
        if isLive {
            // Kleines grünes „LIVE“-Schild unter dem Kreis.
            let badge = UILabel()
            badge.text = "LIVE"
            badge.font = .systemFont(ofSize: 9, weight: .heavy)
            badge.textColor = .white
            badge.textAlignment = .center
            badge.backgroundColor = .systemGreen
            badge.layer.cornerRadius = 6
            badge.layer.masksToBounds = true
            badge.frame = CGRect(x: 4, y: bounds.height - 6, width: bounds.width - 8, height: 12)
            addSubview(badge)
        } else {
            circle.alpha = 0.85
        }
        accessibilityLabel = isLive ? "Live-Position \(mode.displayName)" : "Geschätzte Position \(mode.displayName)"
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }
}

private extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension TransportMode {
    /// SF-Symbol für das Verkehrsmittel.
    var symbolName: String {
        switch self {
        case .tram: "tram.fill"
        case .cityBus, .regionalBus, .onDemand: "bus.fill"
        case .suburbanRailway, .train, .longDistance: "train.side.front.car"
        case .coach: "bus.doubledecker.fill"
        case .subway: "tram.tunnel.fill"
        case .ferry: "ferry.fill"
        case .cableway: "cablecar.fill"
        case .other: "circle.fill"
        }
    }
}

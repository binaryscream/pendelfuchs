// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Suchanfrage für Verbindungen.
public struct TripQuery: Codable, Sendable, Hashable {
    public var origin: Stop
    public var destination: Stop
    public var via: Stop?
    public var time: Date
    /// `true`: `time` ist die gewünschte Ankunft, sonst die Abfahrt.
    public var isArrivalTime: Bool
    public var options: TripOptions

    public init(origin: Stop, destination: Stop, via: Stop? = nil, time: Date = .now, isArrivalTime: Bool = false,
                options: TripOptions = .standard) {
        self.origin = origin
        self.destination = destination
        self.via = via
        self.time = time
        self.isArrivalTime = isArrivalTime
        self.options = options
    }
}

/// Eine Verbindung von A nach B, bestehend aus Fahrten und Fußwegen.
public struct Trip: Codable, Sendable, Hashable, Identifiable {
    public var legs: [TripLeg]
    public var interchanges: Int
    /// Fahrpreis (Einzelfahrt) laut Datenquelle, z. B. „6,30 €“.
    public var price: String?
    /// Tarifzonen, z. B. „TZ Pirna (70), TZ Dresden (10)“.
    public var fareZones: String?
    /// Datenquelle (für die Quellenangabe).
    public var source: ProviderID?

    public init(legs: [TripLeg], interchanges: Int, price: String? = nil, fareZones: String? = nil,
                source: ProviderID? = nil) {
        self.legs = legs
        self.interchanges = interchanges
        self.price = price
        self.fareZones = fareZones
        self.source = source
    }

    /// Stabil über mehrere Suchen hinweg (für „Früher/Später“-Zusammenführung).
    public var id: String {
        rides.map { "\($0.line ?? "?")@\(Int($0.departure?.scheduledTime.timeIntervalSince1970 ?? 0))" }
            .joined(separator: "|")
    }

    public var rides: [TripLeg] { legs.filter { $0.kind == .ride } }

    /// Erster Halt mit Abfahrtszeit.
    public var departure: TimePoint { rides.first?.departure ?? legs.first?.departure ?? .init(scheduledTime: .distantPast) }
    /// Letzter Halt mit Ankunftszeit.
    public var arrival: TimePoint { rides.last?.arrival ?? legs.last?.arrival ?? .init(scheduledTime: .distantPast) }

    public var duration: TimeInterval { arrival.expectedTime.timeIntervalSince(departure.expectedTime) }

    public var isCancelled: Bool { rides.contains { $0.isCancelled } }

    /// Alle Hinweise der Fahrten (ohne Doppelte).
    public var alerts: [ServiceAlert] {
        var seen = Set<String>()
        return rides.flatMap(\.alerts).filter { seen.insert($0.id).inserted }
    }

    /// Gleiswechsel beim Einstieg in eine der Fahrten.
    public var hasPlatformChange: Bool { rides.contains { $0.stops.first?.platformChanged == true } }

    /// Mindestens eine Fahrt der Verbindung fällt ganz aus.
    public var hasCancelledRide: Bool { rides.contains { $0.isFullyCancelled } }

    /// Warum die Verbindung so nicht fahrbar ist (Fahrt fällt aus, Ein- oder Ausstieg entfällt); sonst `nil`.
    /// Entfallene Halte mitten auf der Strecke stören nicht – die Bahn fährt trotzdem.
    public var disruption: TripDisruption? {
        if let ride = rides.first(where: \.isFullyCancelled) { return .rideCancelled(line: ride.line) }
        for ride in rides {
            if let first = ride.stops.first, first.isCancelled { return .boardingCancelled(line: ride.line, stop: first) }
            if let last = ride.stops.last, last.isCancelled { return .alightingCancelled(line: ride.line, stop: last) }
        }
        // Anschluss verpasst: Die erste Fahrt kommt laut Echtzeit erst an, wenn die nächste schon abgefahren ist.
        for (arriving, next) in zip(rides, rides.dropFirst()) {
            if let arrival = arriving.arrival, let departure = next.departure, let stop = next.stops.first,
               arrival.expectedTime > departure.expectedTime {
                return .connectionMissed(line: next.line, stop: stop)
            }
        }
        return nil
    }
}

/// Geplante Zeit plus optionale Echtzeit-Prognose.
public struct TimePoint: Codable, Sendable, Hashable {
    public var scheduledTime: Date
    public var realTime: Date?

    public init(scheduledTime: Date, realTime: Date? = nil) {
        self.scheduledTime = scheduledTime
        self.realTime = realTime
    }

    public var expectedTime: Date { realTime ?? scheduledTime }

    public var delayMinutes: Int? {
        guard let realTime else { return nil }
        return Int((realTime.timeIntervalSince(scheduledTime) / 60).rounded())
    }
}

public struct TripLeg: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case ride, walk }

    public var kind: Kind
    public var mode: TransportMode?
    public var line: String?
    public var direction: String?
    public var operatorName: String?
    /// Alle Halte inkl. Ein- und Ausstieg (bei Fußwegen leer).
    public var stops: [TripStop]
    public var durationMinutes: Int?
    public var notes: [String]
    /// Streckenverlauf für die Karte (leer, wenn die Quelle keinen liefert).
    public var path: [Coordinate]
    /// Zugnummer (z. B. „32712“), falls bekannt.
    public var trainNumber: String?
    /// Störungs-/Baustellenhinweise zu dieser Fahrt (optional gespeichert, damit ältere Daten lesbar bleiben).
    public var alertList: [ServiceAlert]?
    public var alerts: [ServiceAlert] {
        get { alertList ?? [] }
        set { alertList = newValue.isEmpty ? nil : newValue }
    }

    public init(kind: Kind, mode: TransportMode? = nil, line: String? = nil, direction: String? = nil,
                operatorName: String? = nil, stops: [TripStop] = [], durationMinutes: Int? = nil, notes: [String] = [],
                path: [Coordinate] = [], trainNumber: String? = nil) {
        self.trainNumber = trainNumber
        self.kind = kind
        self.mode = mode
        self.line = line
        self.direction = direction
        self.operatorName = operatorName
        self.stops = stops
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.path = path
    }

    /// Streckenverlauf, notfalls die Luftlinie über die Halte.
    public var drawablePath: [Coordinate] {
        path.count >= 2 ? path : stops.compactMap(\.coordinate)
    }

    public var departure: TimePoint? { stops.first?.departure ?? stops.first?.arrival }
    public var arrival: TimePoint? { stops.last?.arrival ?? stops.last?.departure }
    public var intermediateStops: ArraySlice<TripStop> { stops.count > 2 ? stops.dropFirst().dropLast() : [] }
    public var isCancelled: Bool { stops.contains { $0.isCancelled } }

    /// Die ganze Fahrt fällt aus (alle Halte). Dann gibt es keinen Fortschritt und kein Fahrzeug.
    public var isFullyCancelled: Bool { !stops.isEmpty && stops.allSatisfy(\.isCancelled) }

    /// So nicht nutzbar: Die Fahrt fällt ganz aus oder ihr Ein- bzw. Ausstieg entfällt. Ein entfallener
    /// Zwischenhalt zählt nicht – die Bahn fährt trotzdem.
    public var isUnusable: Bool {
        isFullyCancelled || stops.first?.isCancelled == true || stops.last?.isCancelled == true
    }

    /// Auslastung beim Einstieg (erste bekannte Angabe ab dem ersten Halt).
    public var boardingOccupancy: Occupancy? { stops.dropLast().lazy.compactMap(\.occupancy).first }
}

public struct TripStop: Codable, Sendable, Hashable {
    public var stopID: String
    public var name: String
    public var place: String?
    public var platform: String?
    public var arrival: TimePoint?
    public var departure: TimePoint?
    public var isCancelled: Bool
    public var coordinate: Coordinate?
    /// Erwartete Auslastung ab diesem Halt (nur manche Quellen, z. B. VVO).
    public var occupancy: Occupancy?
    /// Geplantes Gleis, wenn die Quelle es getrennt vom aktuellen liefert (Transitous).
    public var scheduledPlatform: String?

    /// Gleiswechsel: aktuelles Gleis weicht vom geplanten ab.
    public var platformChanged: Bool {
        guard let platform, let scheduledPlatform else { return false }
        return platform != scheduledPlatform
    }

    public init(stopID: String, name: String, place: String?, platform: String?,
                arrival: TimePoint?, departure: TimePoint?, isCancelled: Bool = false, coordinate: Coordinate? = nil,
                occupancy: Occupancy? = nil) {
        self.occupancy = occupancy == .unknown ? nil : occupancy
        self.stopID = stopID
        self.name = name
        self.place = place
        self.platform = platform
        self.arrival = arrival
        self.departure = departure
        self.isCancelled = isCancelled
        self.coordinate = coordinate
    }

    /// Zeitpunkt, an dem das Fahrzeug den Halt verlässt (bzw. erreicht, beim letzten Halt).
    public var passTime: Date? { (departure ?? arrival)?.expectedTime }
}


/// Grund, warum eine Verbindung nicht wie geplant fahrbar ist.
public enum TripDisruption: Equatable, Hashable, Sendable {
    case rideCancelled(line: String?)
    case boardingCancelled(line: String?, stop: TripStop)
    case alightingCancelled(line: String?, stop: TripStop)
    /// Umstieg nicht mehr zu schaffen (Verspätung der ersten Fahrt).
    case connectionMissed(line: String?, stop: TripStop)

    /// Kurzer Hinweis, wenn die Verbindung deshalb durch eine andere ersetzt wurde.
    public var rerouteNote: String {
        switch self {
        case .rideCancelled(let line): "\(line ?? "Fahrt") fällt aus – nächste Verbindung"
        case .boardingCancelled, .alightingCancelled: "Halt entfällt – neue Verbindung"
        case .connectionMissed(let line, _): "Anschluss \(line ?? "") verpasst – nächste Verbindung"
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@preconcurrency import TripKit
import TripKitBridge

/// Regionale Verbünde, deren Auskunft die App über **TripKit** (github.com/alexander-albers/tripkit, MIT;
/// eingebunden über den Fork github.com/binaryscream/tripkit mit einstellbarem User-Agent) abfragt.
///
/// Nur Verbünde mit EFA-Schnittstelle, die ohne Schlüssel auskommt. Regionen, deren Schnittstelle eine Kennung
/// verlangt (HAFAS), bleiben bei Transitous – Kennungen fremder Apps werden bewusst nicht verwendet.
/// Die Schnittstellen sind die Auskunftssysteme der Verbünde selbst, für Drittanbieter nicht offiziell
/// freigegeben (siehe `docs/DATENQUELLEN.md`).
public enum RegionalNetwork: String, Codable, Sendable, CaseIterable {
    /// Verkehrsverbund Mittelsachsen (Chemnitz, Erzgebirge, Mittelsachsen, Zwickau).
    case vms
    /// Verkehrsverbund Vogtland.
    case vvv
    /// Bayern-Fahrplan der Bayerischen Eisenbahngesellschaft (ganz Bayern).
    case bayern
    /// Nahverkehrsgesellschaft Baden-Württemberg (ganz Baden-Württemberg).
    case nvbw
    /// mobil.nrw (ganz Nordrhein-Westfalen).
    case nrw
    /// Mecklenburg-Vorpommern.
    case vmv

    public var providerID: ProviderID { ProviderID(rawValue: rawValue)! }

    /// User-Agent für alle Anfragen über TripKit. Gilt in TripKit global; ohne ihn schickt TripKit einen
    /// Safari-User-Agent. Einstellbar erst im Fork github.com/binaryscream/tripkit (`HttpClient.defaultUserAgent`).
    public static var userAgent: String {
        get { HttpClient.defaultUserAgent }
        set { HttpClient.defaultUserAgent = newValue }
    }

    /// Wird je Anfrage neu erzeugt: Die TripKit-Klassen sind nicht `Sendable`, aber zustandslos genug.
    func makeProvider() -> TKNetworkProvider {
        switch self {
        case .vms: VmsProvider()
        case .vvv: VvvProvider()
        case .bayern: BayernProvider()
        case .nvbw: NvbwProvider()
        case .nrw: NrwProvider()
        case .vmv: VmvProvider()
        }
    }

    /// Zuständiger Verbund für einen Kreis (amtlicher Gemeindeschlüssel, die ersten fünf Stellen der DHID).
    /// Das VVO-Gebiet fehlt bewusst: Dafür gibt es die eigene VVO-Anbindung.
    public static func forDistrict(_ district: String) -> RegionalNetwork? {
        switch district {
        case "14511", "14521", "14522", "14524": return .vms   // Chemnitz, Erzgebirge, Mittelsachsen, Zwickau
        case "14523": return .vvv                             // Vogtlandkreis
        default: break
        }
        switch district.prefix(2) {
        case "09": return .bayern
        case "08": return .nvbw
        case "05": return .nrw
        case "13": return .vmv
        default: return nil
        }
    }

    /// Verbund für eine Haltestelle: aus der Quelle selbst oder aus dem Kreis der bundesweiten Haltestellen-ID
    /// (`de-DELFI_de:09162:6:…` → Kreis `09162` → Bayern).
    public static func `for`(_ stop: Stop) -> RegionalNetwork? {
        if let network = stop.provider.regionalNetwork { return network }
        guard stop.provider == .transitous else { return nil }
        return district(of: stop.stopID).flatMap(forDistrict)
    }

    static func district(of stopID: String) -> String? { DHID(transitousID: stopID)?.district }

    /// Transitous-Haltestelle ohne bundesweite ID (Fernbus-Halte, ausländische Datensätze): Die Region ist
    /// unbekannt, nicht „außerhalb“.
    public static func isUnplaced(_ stop: Stop) -> Bool {
        stop.provider == .transitous && DHID(transitousID: stop.stopID) == nil && stop.coordinate != nil
    }
}

/// Bundesweite Haltestellen-ID (`de:Kreis:Nummer:…`) aus einer Transitous-Kennung, egal mit welchem Präfix.
struct DHID: Equatable {
    /// Amtlicher Kreisschlüssel, z. B. `14612` (Dresden).
    var district: String
    var number: String

    init?(transitousID id: String) {
        // Präfix (Datensatz) abtrennen: alles bis einschließlich des letzten `_` vor `de:`.
        guard let range = id.range(of: "de:") else { return nil }
        let before = id[..<range.lowerBound]
        guard before.isEmpty || before.hasSuffix("_") else { return nil }
        let parts = id[range.lowerBound...].split(separator: ":")
        guard parts.count >= 3, parts[1].count == 5, parts[1].allSatisfy(\.isNumber) else { return nil }
        district = String(parts[1])
        number = String(parts[2])
    }
}

/// Datenquelle für einen regionalen Verbund über TripKit.
public struct RegionalProvider: TransitProvider {
    public let network: RegionalNetwork
    public var id: ProviderID { network.providerID }

    public init(network: RegionalNetwork) {
        self.network = network
    }

    // MARK: Haltestellen

    public func searchStops(query: String) async throws -> [Stop] {
        let (_, result) = await network.makeProvider().suggestLocations(constraint: query, types: [.station], maxLocations: 20)
        switch result {
        case .success(let locations): return locations.compactMap { stop(from: $0.location) }
        case .failure(let error): throw error
        }
    }

    public func nearbyStops(around coordinate: Coordinate) async throws -> [Stop] {
        let here = TKLocation(lat: Int(coordinate.latitude * 1e6), lon: Int(coordinate.longitude * 1e6))
        let (_, result) = await network.makeProvider().queryNearbyLocations(location: here, types: [.station],
                                                                          maxDistance: 1000, maxLocations: 20)
        switch result {
        case .success(let locations):
            return locations.compactMap { location -> Stop? in
                guard var stop = stop(from: location) else { return nil }
                stop.distance = stop.coordinate.map { Int(Geo.meters(coordinate, $0).rounded()) }
                return stop
            }.sorted { ($0.distance ?? .max) < ($1.distance ?? .max) }
        case .invalidId: return []
        case .failure(let error): throw error
        }
    }

    /// Dieselbe Haltestelle in diesem Verbund: über Lage und Namen, weil die Kennungen der Verbünde nicht mit der
    /// bundesweiten Haltestellen-ID übereinstimmen.
    public func resolve(_ stop: Stop) async throws -> Stop {
        if stop.provider == id { return stop }
        if let known = await RegionalStopCache.shared.get(network, stop.id) { return known }

        var candidates: [Stop] = []
        if let coordinate = stop.coordinate {
            candidates = (try? await nearbyStops(around: coordinate)) ?? []
        }
        if candidates.isEmpty {
            candidates = try await searchStops(query: [stop.place, stop.name].compactMap { $0 }.joined(separator: " "))
        }
        guard let match = Self.bestMatch(for: stop, in: candidates) else {
            throw TransitError.service(message: "Die Haltestelle „\(stop.displayName)“ ist beim \(network.providerID.displayName) nicht bekannt.")
        }
        await RegionalStopCache.shared.set(network, stop.id, match)
        return match
    }

    /// Nächstgelegener Kandidat (höchstens 400 m); ohne Lage der erste mit gleichem Namen.
    static func bestMatch(for stop: Stop, in candidates: [Stop]) -> Stop? {
        if let here = stop.coordinate {
            let near = candidates.compactMap { c in c.coordinate.map { (c, Geo.meters(here, $0)) } }
                .filter { $0.1 <= 400 }
            // Bei mehreren nahen Treffern den mit passendem Namen bevorzugen.
            let named = near.filter { names(match: $0.0, stop) }
            return (named.isEmpty ? near : named).min { $0.1 < $1.1 }?.0
        }
        return candidates.first { names(match: $0, stop) }
    }

    static func names(match a: Stop, _ b: Stop) -> Bool {
        func key(_ s: Stop) -> String { s.name.lowercased().replacingOccurrences(of: " ", with: "") }
        return key(a).contains(key(b)) || key(b).contains(key(a))
    }

    // MARK: Abfahrten

    public func departures(at stop: Stop, limit: Int, from: Date?) async throws -> [Departure] {
        let local = try await resolve(stop)
        let (_, result) = await network.makeProvider().queryDepartures(stationId: local.stopID, departures: true,
                                                                      time: from, maxDepartures: limit, equivs: false)
        switch result {
        case .success(let boards):
            return boards.flatMap(\.departures).map(departure(from:))
                .sorted { $0.expectedTime < $1.expectedTime }
                .prefix(limit).map { $0 }
        case .invalidStation:
            throw TransitError.service(message: "Die Haltestelle „\(stop.displayName)“ ist beim \(network.providerID.displayName) nicht bekannt.")
        case .failure(let error):
            throw error
        }
    }

    func departure(from d: TKDeparture) -> Departure {
        let line = Self.lineName(d.line)
        let direction = (d.destination?.name ?? d.line.name ?? "").tidiedCase
        let state: DepartureState = d.cancelled ? .cancelled
            : d.predictedTime == nil ? .unknown
            : (d.predictedTime!.timeIntervalSince(d.plannedTime) >= 60 ? .delayed : .onTime)
        var result = Departure(id: "\(network.rawValue):\(line)|\(Int(d.plannedTime.timeIntervalSince1970))|\(direction)",
                               line: line, direction: direction, platform: d.platform,
                               mode: Self.mode(of: d.line), scheduledTime: d.plannedTime, realTime: d.predictedTime,
                               state: state, occupancy: .unknown, source: id,
                               tripID: d.journeyContext.flatMap(Self.encode))
        if let planned = d.plannedPlatform, let predicted = d.predictedPlatform, planned != predicted {
            result.scheduledPlatform = planned
        }
        return result
    }

    // MARK: Fahrtverlauf

    public func journey(of departure: Departure, at stop: Stop) async throws -> TripLeg {
        guard let token = departure.tripID, let context = Self.decode(token) else {
            throw TransitError.service(message: "Für diese Fahrt ist kein Fahrtverlauf verfügbar.")
        }
        let (_, result) = await network.makeProvider().queryJourneyDetail(context: context)
        switch result {
        case .success(_, let leg): return tripLeg(from: leg)
        case .invalidId: throw TransitError.service(message: "Der Fahrtverlauf ist nicht mehr verfügbar.")
        case .failure(let error): throw error
        }
    }

    /// Der Kontext für den Fahrtverlauf passt in die Kennung der Abfahrt – so funktioniert er auch im Widget.
    static func encode(_ context: TKJourneyContext) -> String? {
        try? NSKeyedArchiver.archivedData(withRootObject: context, requiringSecureCoding: true).base64EncodedString()
    }

    static func decode(_ token: String) -> TKJourneyContext? {
        guard let data = Data(base64Encoded: token) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [TKEfaJourneyContext.self, TKLine.self,
                                                                  NSString.self, NSDate.self, NSArray.self,
                                                                  NSNumber.self], from: data) as? TKJourneyContext
    }

    // MARK: Verbindungen

    public func trips(_ query: TripQuery) async throws -> [Trip] {
        let origin = try await resolve(query.origin)
        let destination = try await resolve(query.destination)
        let via = try await query.via.asyncMap(resolve)
        let options = query.options

        var products: [TKProduct] = []
        for group in ModeGroup.allCases where options.allowedModes.contains(group) {
            switch group {
            case .regionalRail: products += [.regionalTrain, .suburbanTrain]
            case .longDistance: products += [.highSpeedTrain]
            case .subway: products += [.subway]
            case .tram: products += [.tram]
            case .bus, .coach: products += [.bus]
            case .ferry: products += [.ferry]
            case .cableway: products += [.cablecar]
            case .onDemand: products += [.onDemand]
            }
        }
        let walk: TKWalkSpeed = switch options.walkingSpeed {
        case .slow: .slow
        case .normal: .normal
        case .fast: .fast
        }
        let tripOptions = TKTripOptions(products: Array(Set(products)), walkSpeed: walk, maxChanges: options.maxTransfers)

        let (_, result) = await network.makeProvider().queryTrips(
            from: Self.location(origin), via: via.map(Self.location), to: Self.location(destination),
            date: query.time, departure: !query.isArrivalTime, tripOptions: tripOptions)
        switch result {
        case .success(_, _, _, _, let trips, _):
            return trips.compactMap(trip(from:))
                .filter(options.allows)
                .sorted { $0.departure.expectedTime < $1.departure.expectedTime }
        case .noTrips, .tooClose:
            return []
        case .failure(let error):
            throw error
        default:
            throw TransitError.service(message: "Der \(network.providerID.displayName) hat keine Verbindung gefunden.")
        }
    }

    static func location(_ stop: Stop) -> TKLocation {
        TKLocation(type: .station, id: stop.stopID,
                   coord: stop.coordinate.map { TKLocationPoint(lat: Int($0.latitude * 1e6), lon: Int($0.longitude * 1e6)) },
                   place: stop.place, name: stop.name, products: nil) ?? TKLocation(id: stop.stopID)
    }

    func trip(from t: TKTrip) -> Trip? {
        var legs: [TripLeg] = []
        for leg in t.legs {
            if let ride = leg as? TKPublicLeg {
                legs.append(tripLeg(from: ride))
            } else if let walk = leg as? TKIndividualLeg {
                let minutes = max(0, walk.min)
                if let last = legs.last, last.kind == .walk {
                    legs[legs.count - 1].durationMinutes = (last.durationMinutes ?? 0) + minutes
                } else {
                    legs.append(TripLeg(kind: .walk, durationMinutes: minutes,
                                        path: walk.path.map(Self.coordinate)))
                }
            }
        }
        while let first = legs.first, first.kind == .walk, (first.durationMinutes ?? 0) == 0 { legs.removeFirst() }
        while let last = legs.last, last.kind == .walk, (last.durationMinutes ?? 0) == 0 { legs.removeLast() }
        let rides = legs.filter { $0.kind == .ride }.count
        guard rides > 0 else { return nil }
        let (price, zones) = Self.price(from: t.fares)
        return Trip(legs: legs, interchanges: max(0, rides - 1), price: price, fareZones: zones, source: id)
    }

    /// Einzelfahrt für Erwachsene, z. B. („11,50 €“, „Preisstufe VR“) – wie beim VVO. Nicht jeder Verbund liefert
    /// Preise (Bayern, NVBW, MV liefern keine).
    static func price(from fares: [TKFare]) -> (price: String?, zones: String?) {
        guard let adult = fares.first(where: { $0.type == .adult }) ?? fares.first else { return (nil, nil) }
        return price(amount: Double(adult.fare), currency: adult.currency, unitsName: adult.unitsName, units: adult.units)
    }

    static func price(amount: Double, currency: String, unitsName: String?, units: String?) -> (price: String?, zones: String?) {
        guard amount > 0 else { return (nil, nil) }
        // Gleiche Schreibweise wie beim VVO („6,30 €“), mit normalem Leerzeichen.
        let number = String(format: "%.2f", amount).replacingOccurrences(of: ".", with: ",")
        let price = currency == "EUR" ? "\(number) €" : "\(number) \(currency)"
        let name = unitsName?.trimmingCharacters(in: .whitespaces) ?? ""
        let value = units?.trimmingCharacters(in: .whitespaces) ?? ""
        let zones: String? = value.isEmpty ? nil : "\(name.isEmpty ? "Preisstufe" : name) \(value)"
        return (price, zones)
    }

    func tripLeg(from leg: TKPublicLeg) -> TripLeg {
        var stops = [tripStop(leg.departureStop.location, arrival: nil, departure: leg.departureStop)]
        for stop in leg.intermediateStops {
            stops.append(tripStop(stop.location, arrival: stop.arrival, departure: stop.departure))
        }
        stops.append(tripStop(leg.arrivalStop.location, arrival: leg.arrivalStop, departure: nil))
        let line = Self.lineName(leg.line)
        let minutes = Int((leg.arrivalStop.plannedTime.timeIntervalSince(leg.departureStop.plannedTime) / 60).rounded())
        return TripLeg(kind: .ride, mode: Self.mode(of: leg.line), line: line,
                       direction: (leg.destination?.name).map(\.tidiedCase),
                       operatorName: nil, stops: stops, durationMinutes: minutes,
                       notes: [leg.message, leg.line.message].compactMap { $0 }.filter { !$0.isEmpty },
                       path: leg.path.map(Self.coordinate))
    }

    func tripStop(_ location: TKLocation, arrival: TKStopEvent?, departure: TKStopEvent?) -> TripStop {
        func point(_ event: TKStopEvent?) -> TimePoint? {
            event.map { TimePoint(scheduledTime: $0.plannedTime, realTime: $0.predictedTime) }
        }
        let event = departure ?? arrival
        var stop = TripStop(stopID: location.id ?? "", name: location.name ?? location.place ?? "",
                            place: location.place, platform: event?.platform,
                            arrival: point(arrival), departure: point(departure),
                            isCancelled: event?.cancelled ?? false, coordinate: location.coord.map(Self.coordinate))
        if let planned = event?.plannedPlatform, let predicted = event?.predictedPlatform, planned != predicted {
            stop.scheduledPlatform = planned
        }
        return stop
    }

    // MARK: Umrechnung

    func stop(from location: TKLocation) -> Stop? {
        guard let id = location.id, let name = location.name else { return nil }
        return Stop(provider: self.id, stopID: id, name: name, place: location.place,
                    coordinate: location.coord.map(Self.coordinate))
    }

    static func coordinate(_ point: TKLocationPoint) -> Coordinate {
        Coordinate(latitude: Double(point.lat) / 1e6, longitude: Double(point.lon) / 1e6)
    }

    static func lineName(_ line: TKLine) -> String {
        let raw = line.label ?? line.name ?? line.number ?? "?"
        return raw.trimmingCharacters(in: .whitespaces)
    }

    static func mode(of line: TKLine) -> TransportMode {
        switch line.product {
        case .highSpeedTrain: return .longDistance
        case .regionalTrain: return .train
        case .suburbanTrain: return .suburbanRailway
        case .subway: return .subway
        case .tram: return .tram
        case .bus:
            // Stadtbusse haben meist kurze Nummern, Regionalbusse längere.
            let name = lineName(line)
            return name.count <= 3 && name.allSatisfy(\.isNumber) ? .cityBus : .regionalBus
        case .onDemand: return .onDemand
        case .ferry: return .ferry
        case .cablecar: return .cableway
        case nil: return .other
        }
    }
}

/// Merkt sich, welche Verbund-Haltestelle zu einer bundesweiten Haltestelle gehört (nur während die App läuft).
actor RegionalStopCache {
    static let shared = RegionalStopCache()
    private var stops: [String: Stop] = [:]

    func get(_ network: RegionalNetwork, _ id: String) -> Stop? { stops["\(network.rawValue)|\(id)"] }
    func set(_ network: RegionalNetwork, _ id: String, _ stop: Stop) { stops["\(network.rawValue)|\(id)"] = stop }
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Datenquelle für ganz Deutschland (und Europa) über Transitous (MOTIS 2 API).
///
/// Nutzungsbedingungen (transitous.org/api): nur für kostenlose Open-Source-Apps, User-Agent mit
/// App-Name, Version und Kontakt, sichtbarer Link auf https://transitous.org/sources/ plus
/// OpenStreetMap-Nennung. Siehe `docs/DATENQUELLEN.md`.
public struct TransitousProvider: TransitProvider {
    public let id: ProviderID = .transitous

    /// Kontaktangabe für Transitous (Pflicht laut Nutzungsbedingungen).
    public static let contactURL = "https://github.com/binaryscream/fahrplan-xl"

    /// App-Name, Version und Kontakt, z. B. `FahrplanXL/0.1.0 (+https://github.com/…)`.
    public static func userAgent(version: String) -> String {
        "FahrplanXL/\(version) (+\(contactURL))"
    }

    public static let defaultUserAgent = userAgent(version: "dev")

    private let baseURL: URL
    private let session: URLSession
    private let userAgent: String

    public init(baseURL: URL = URL(string: "https://api.transitous.org/api")!,
                userAgent: String = TransitousProvider.defaultUserAgent,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.session = session
    }

    // MARK: TransitProvider

    public func searchStops(query: String) async throws -> [Stop] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let matches: [TransitousAPI.Match] = try await get("v1/geocode", [
            "text": trimmed, "type": "STOP", "language": "de",
        ])
        return TransitousAPI.uniqueStops(matches.map { $0.stop(distanceFrom: nil) })
    }

    public func nearbyStops(around coordinate: Coordinate) async throws -> [Stop] {
        let matches: [TransitousAPI.Match] = try await get("v1/reverse-geocode", [
            "place": "\(coordinate.latitude),\(coordinate.longitude)", "type": "STOP", "numResults": "15",
        ])
        return TransitousAPI.uniqueStops(matches.map { $0.stop(distanceFrom: coordinate) })
            .sorted { ($0.distance ?? .max) < ($1.distance ?? .max) }
    }

    public func departures(at stop: Stop, limit: Int = 20) async throws -> [Departure] {
        let response: TransitousAPI.StopTimesResponse = try await get("v6/stoptimes", [
            "stopId": stop.stopID, "n": String(limit), "language": "de",
        ])
        return response.stopTimes.compactMap(\.departure).sorted { $0.expectedTime < $1.expectedTime }
    }

    public func trips(_ query: TripQuery) async throws -> [Trip] {
        var params = [
            "fromPlace": query.origin.stopID,
            "toPlace": query.destination.stopID,
            "time": TransitousAPI.requestTime(query.time),
            "arriveBy": query.isArrivalTime ? "true" : "false",
            "language": "de",
        ]
        if let via = query.via { params["via"] = via.stopID }
        let options = query.options
        if options.allowedModes != Set(ModeGroup.allCases) {
            params["transitModes"] = TransitousAPI.transitModes(for: options.allowedModes).joined(separator: ",")
        }
        if let maxTransfers = options.maxTransfers { params["maxTransfers"] = String(maxTransfers) }
        if options.walkingSpeed != .normal { params["pedestrianSpeed"] = String(options.walkingSpeed.metersPerSecond) }

        let response: TransitousAPI.PlanResponse = try await get("v6/plan", params)
        return response.itineraries.compactMap(\.trip)
            .filter(options.allows)
            .sorted { $0.departure.expectedTime < $1.departure.expectedTime }
    }

    public func journey(of departure: Departure, at stop: Stop) async throws -> TripLeg {
        guard let tripID = departure.tripID else {
            throw TransitError.service(message: "Für diese Fahrt ist kein Fahrtverlauf verfügbar.")
        }
        let itinerary: TransitousAPI.Itinerary = try await get("v6/trip", ["tripId": tripID, "language": "de"])
        guard let leg = itinerary.legs.compactMap(\.tripLeg).first(where: { $0.kind == .ride }) else {
            throw TransitError.service(message: "Der Fahrtverlauf ist leer.")
        }
        return leg
    }

    // MARK: HTTP

    private func get<T: Decodable>(_ path: String, _ params: [String: String]) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TransitError.badResponse(status: http.statusCode)
        }
        return try TransitousAPI.decode(T.self, from: data)
    }
}

// MARK: - Antwortformate (Auszug aus der MOTIS-2-OpenAPI)

enum TransitousAPI {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Datum \(raw)"))
            }
            return date
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw TransitError.decoding(String(describing: error))
        }
    }

    /// ISO 8601 mit oder ohne Sekundenbruchteile, z. B. `2026-11-23T21:10:00Z`.
    static func parseDate(_ raw: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: raw) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }

    static func requestTime(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func mode(_ raw: String?) -> TransportMode {
        switch raw {
        case "TRAM", "CABLE_CAR": .tram
        case "BUS": .cityBus
        case "COACH": .coach
        case "SUBURBAN": .suburbanRailway
        case "SUBWAY", "METRO": .subway
        case "RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL": .train
        case "LONG_DISTANCE", "HIGHSPEED_RAIL", "NIGHT_RAIL": .longDistance
        case "FERRY": .ferry
        case "AERIAL_LIFT", "FUNICULAR": .cableway
        case "ODM", "FLEX": .onDemand
        default: .other
        }
    }

    /// „Gl. 5“ → „5“ (die App setzt „Gl.“/„Steig“ selbst davor).
    static func platform(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        for prefix in ["Gleis ", "Gl. ", "Gl.", "Steig "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        return value
    }

    /// Ergebnisse auf Bahnsteig-Ebene (`…:1:1`) zu einer Haltestelle zusammenfassen.
    static func uniqueStops(_ stops: [Stop]) -> [Stop] {
        var seen = Set<String>()
        return stops.filter { seen.insert("\($0.place ?? "")|\($0.name)").inserted }
    }

    /// Haversine-Entfernung in Metern.
    static func meters(_ a: Coordinate, _ b: Coordinate) -> Int {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return Int((2 * r * asin(sqrt(h))).rounded())
    }

    /// „Pirna Bahnhof“ + Ort „Pirna“ → Name „Bahnhof“, Ort „Pirna“.
    static func split(name: String, place: String?) -> (name: String, place: String?) {
        guard let place, !place.isEmpty else { return (name, nil) }
        // Bahnhof heißt wie der Ort („Leipzig“) → Ort nicht doppelt anzeigen.
        if name == place { return (name, nil) }
        for separator in [" ", ", ", " - "] {
            let prefix = place + separator
            if name.hasPrefix(prefix), name.count > prefix.count {
                return (String(name.dropFirst(prefix.count)), place)
            }
        }
        return (name, place)
    }

    // MARK: Geocode

    struct Match: Decodable {
        struct Area: Decodable {
            let name: String
            let adminLevel: Double?
            let `default`: Bool?
        }

        let type: String
        let name: String
        let id: String
        let lat: Double
        let lon: Double
        let areas: [Area]?

        /// Der „Standard“-Bereich ist der Ort (z. B. „Pirna“), sonst die feinste Verwaltungsebene ≥ 7.
        var placeName: String? {
            if let area = areas?.first(where: { $0.default == true }) { return area.name }
            return areas?.filter { ($0.adminLevel ?? 0) >= 7 }.min { ($0.adminLevel ?? 0) < ($1.adminLevel ?? 0) }?.name
        }

        func stop(distanceFrom origin: Coordinate?) -> Stop {
            let coordinate = Coordinate(latitude: lat, longitude: lon)
            let parts = TransitousAPI.split(name: name, place: placeName)
            return Stop(provider: .transitous, stopID: id, name: parts.name, place: parts.place,
                        coordinate: coordinate, distance: origin.map { TransitousAPI.meters($0, coordinate) })
        }
    }

    // MARK: Stoptimes / Place

    struct Place: Decodable {
        let name: String
        let stopId: String?
        let lat: Double?
        let lon: Double?
        let arrival: Date?
        let departure: Date?
        let scheduledArrival: Date?
        let scheduledDeparture: Date?
        let track: String?
        let scheduledTrack: String?
        let cancelled: Bool?

        func tripStop(realTime: Bool) -> TripStop {
            func point(_ scheduled: Date?, _ actual: Date?) -> TimePoint? {
                guard let scheduled else { return actual.map { TimePoint(scheduledTime: $0) } }
                return TimePoint(scheduledTime: scheduled, realTime: realTime ? actual : nil)
            }
            var coordinate: Coordinate?
            if let lat, let lon { coordinate = Coordinate(latitude: lat, longitude: lon) }
            return TripStop(stopID: stopId ?? "", name: name, place: nil,
                            platform: TransitousAPI.platform(track ?? scheduledTrack),
                            arrival: point(scheduledArrival, arrival),
                            departure: point(scheduledDeparture, departure),
                            isCancelled: cancelled ?? false,
                            coordinate: coordinate)
        }
    }

    struct StopTimesResponse: Decodable {
        let stopTimes: [StopTime]
    }

    struct StopTime: Decodable {
        let place: Place
        let mode: String?
        let realTime: Bool?
        let headsign: String?
        let tripTo: Place?
        let routeShortName: String?
        let displayName: String?
        let tripShortName: String?
        let tripId: String?
        let cancelled: Bool?
        let tripCancelled: Bool?

        var departure: Departure? {
            guard let scheduled = place.scheduledDeparture ?? place.departure else { return nil }
            let hasRealTime = realTime ?? false
            let actual = hasRealTime ? place.departure : nil
            let isCancelled = (cancelled ?? false) || (tripCancelled ?? false) || (place.cancelled ?? false)
            let delay = actual.map { $0.timeIntervalSince(scheduled) } ?? 0
            let state: DepartureState = isCancelled ? .cancelled
                : !hasRealTime ? .unknown
                : delay >= 60 ? .delayed : .onTime
            let line = TransitousAPI.lineName(displayName: displayName, routeShortName: routeShortName,
                                              tripShortName: tripShortName, mode: mode)
            return Departure(
                id: "\(tripId ?? line)@\(Int(scheduled.timeIntervalSince1970))",
                line: line,
                direction: headsign ?? tripTo?.name ?? "",
                platform: TransitousAPI.platform(place.track ?? place.scheduledTrack),
                mode: TransitousAPI.mode(mode),
                scheduledTime: scheduled,
                realTime: actual,
                state: state,
                occupancy: .unknown,
                source: .transitous,
                tripID: tripId
            )
        }
    }

    /// MOTIS-Verkehrsmittel für die erlaubten Gruppen.
    static func transitModes(for groups: Set<ModeGroup>) -> [String] {
        var modes: [String] = []
        for group in ModeGroup.allCases where groups.contains(group) {
            switch group {
            case .regionalRail: modes += ["SUBURBAN", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "RAIL"]
            case .longDistance: modes += ["LONG_DISTANCE", "HIGHSPEED_RAIL", "NIGHT_RAIL"]
            case .subway: modes += ["SUBWAY", "METRO"]
            case .tram: modes += ["TRAM", "CABLE_CAR"]
            case .bus: modes += ["BUS"]
            case .coach: modes += ["COACH"]
            case .ferry: modes += ["FERRY"]
            case .cableway: modes += ["AERIAL_LIFT", "FUNICULAR"]
            case .onDemand: modes += ["ODM"]
            }
        }
        return modes
    }

    /// Kurze Linienbezeichnung: „S1“, „RE50“, „ICE 1650“ (nicht die lange Routenbezeichnung).
    /// Bei Fernzügen steht im Kurznamen oft nur die Liniennummer („50“) – dort den Anzeigenamen nehmen.
    static func lineName(displayName: String?, routeShortName: String?, tripShortName: String?,
                         mode: String? = nil) -> String {
        let order = mode.map(TransitousAPI.mode) == .longDistance
            ? [displayName, tripShortName, routeShortName]
            : [routeShortName, displayName, tripShortName]
        for candidate in order {
            if let value = candidate?.trimmingCharacters(in: .whitespaces), !value.isEmpty { return value }
        }
        return "?"
    }

    // MARK: Plan

    struct PlanResponse: Decodable {
        let itineraries: [Itinerary]
    }

    struct Itinerary: Decodable {
        let transfers: Int?
        let legs: [Leg]

        var trip: Trip? {
            var result: [TripLeg] = []
            for leg in legs {
                guard let converted = leg.tripLeg else { continue }
                if converted.kind == .walk, let last = result.last, last.kind == .walk {
                    result[result.count - 1].durationMinutes = (last.durationMinutes ?? 0) + (converted.durationMinutes ?? 0)
                } else {
                    result.append(converted)
                }
            }
            // Fußwege ohne Dauer am Anfang/Ende weglassen.
            while let first = result.first, first.kind == .walk, (first.durationMinutes ?? 0) == 0 { result.removeFirst() }
            while let last = result.last, last.kind == .walk, (last.durationMinutes ?? 0) == 0 { result.removeLast() }
            let rides = result.filter { $0.kind == .ride }.count
            guard rides > 0 else { return nil }
            return Trip(legs: result, interchanges: transfers ?? max(0, rides - 1), source: .transitous)
        }
    }

    struct Leg: Decodable {
        let mode: String
        let duration: Int?
        let from: Place
        let to: Place
        let intermediateStops: [Place]?
        let realTime: Bool?
        let headsign: String?
        let routeShortName: String?
        let displayName: String?
        let tripShortName: String?
        let agencyName: String?
        let cancelled: Bool?
        let legGeometry: Geometry?

        struct Geometry: Decodable {
            let points: String
            let precision: Int?
        }

        var path: [Coordinate] {
            guard let legGeometry else { return [] }
            return Geo.decodePolyline(legGeometry.points, precision: legGeometry.precision ?? 6)
        }

        var tripLeg: TripLeg? {
            let minutes = Int(((Double(duration ?? 0)) / 60).rounded())
            switch mode {
            case "WALK", "BIKE", "CAR", "RENTAL", "CAR_PARKING", "CAR_DROPOFF", "FLEX_WALK":
                return TripLeg(kind: .walk, durationMinutes: minutes)
            default:
                let rt = realTime ?? false
                var stops = [from.tripStop(realTime: rt)] + (intermediateStops ?? []).map { $0.tripStop(realTime: rt) }
                    + [to.tripStop(realTime: rt)]
                if cancelled == true { for i in stops.indices { stops[i].isCancelled = true } }
                return TripLeg(
                    kind: .ride,
                    mode: TransitousAPI.mode(mode),
                    line: TransitousAPI.lineName(displayName: displayName, routeShortName: routeShortName,
                                                 tripShortName: tripShortName, mode: mode),
                    direction: headsign,
                    operatorName: agencyName,
                    stops: stops,
                    durationMinutes: minutes,
                    path: path
                )
            }
        }
    }
}

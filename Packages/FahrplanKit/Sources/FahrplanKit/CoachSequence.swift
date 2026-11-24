// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Wagenreihung eines Zuges an einem Bahnsteig: Wagen mit Position, Klasse und Ausstattung, dazu die Abschnitte.
public struct CoachSequence: Sendable, Hashable {
    public struct Sector: Sendable, Hashable {
        public var name: String
        public var start: Double
        public var end: Double
    }

    public struct Coach: Sendable, Hashable, Identifiable {
        public enum Kind: Sendable, Hashable { case coach, controlCar, locomotive, powerCar }

        public var id: Int
        /// Wagennummer laut Reservierung („1“, „12“); fehlt bei Loks und oft bei S-Bahnen.
        public var number: String?
        public var kind: Kind
        public var firstClass: Bool
        public var secondClass: Bool
        public var doubleDeck: Bool
        public var dining: Bool
        public var closed: Bool
        /// Lage am Bahnsteig in Metern.
        public var start: Double
        public var end: Double
        public var sector: String?
        public var bikes: Bool
        public var wheelchair: Bool
        public var quietZone: Bool
        public var familyZone: Bool
        /// Zugteil (bei Flügelzügen fahren die Teile zu verschiedenen Zielen).
        public var group: Int
        public var destination: String?
    }

    public var platform: String?
    public var platformStart: Double
    public var platformEnd: Double
    public var sectors: [Sector]
    public var coaches: [Coach]

    /// Bereich des Bahnsteigs, den der Zug belegt.
    public var trainStart: Double { coaches.map(\.start).min() ?? platformStart }
    public var trainEnd: Double { coaches.map(\.end).max() ?? platformEnd }

    /// Ziele der Zugteile in Reihenfolge (mehr als eins = Zug wird geteilt).
    public var destinations: [String] {
        var seen: [String] = []
        for coach in coaches { if let d = coach.destination, !seen.contains(d) { seen.append(d) } }
        return seen
    }
}

/// Wagenreihung über die (inoffizielle) Web-Schnittstelle von bahn.de. Kann jederzeit ausfallen oder sich ändern.
public struct DBCoachSequenceProvider: Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://www.bahn.de/web/api/")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Gibt es für diese Fahrt überhaupt eine Wagenreihung? (Zug mit Zugnummer und Koordinate am Einstieg.)
    public static func supports(_ leg: TripLeg) -> Bool {
        guard leg.kind == .ride, leg.trainNumber != nil, leg.stops.first?.coordinate != nil else { return false }
        return [.suburbanRailway, .train, .longDistance].contains(leg.mode ?? .other)
    }

    /// Wagenreihung am Einstieg der Fahrt; `nil`, wenn die DB keine kennt.
    public func coachSequence(for leg: TripLeg) async throws -> CoachSequence? {
        guard Self.supports(leg), let number = leg.trainNumber, let board = leg.stops.first,
              let coordinate = board.coordinate, let departure = (board.departure ?? board.arrival)?.scheduledTime
        else { return nil }
        guard let eva = try await evaNumber(near: coordinate) else { return nil }

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let day = berlin.dateComponents([.year, .month, .day], from: departure)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let data = try await get("reisebegleitung/wagenreihung/vehicle-sequence", [
            "administrationId": "80",
            "category": Self.category(line: leg.line, mode: leg.mode),
            "date": String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0),
            "evaNumber": eva,
            "number": number,
            "time": iso.string(from: departure),
        ])
        guard let data else { return nil }
        return try DBDecoding.coachSequence(from: data)
    }

    /// DB-Bahnhofsnummer (EVA) des nächsten Bahnhofs mit Zügen im Umkreis von 1 km.
    func evaNumber(near coordinate: Coordinate) async throws -> String? {
        let key = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
        if let cached = await EvaCache.shared.value(for: key) { return cached }
        guard let data = try await get("reiseloesung/orte/nearby", [
            "lat": String(coordinate.latitude), "long": String(coordinate.longitude), "radius": "1000", "maxNo": "10",
        ]) else { return nil }
        let eva = try DBDecoding.trainStation(from: data)
        if let eva { await EvaCache.shared.set(eva, for: key) }
        return eva
    }

    /// Zuggattung für die Abfrage („S2“ → „S“, „RB71“ → „RB“, „ICE 905“ → „ICE“). Die Schnittstelle ist hier tolerant.
    static func category(line: String?, mode: TransportMode?) -> String {
        let letters = (line ?? "").uppercased().prefix { $0.isLetter }
        if !letters.isEmpty { return String(letters) }
        switch mode {
        case .suburbanRailway: return "S"
        case .longDistance: return "IC"
        default: return "RB"
        }
    }

    /// `nil` bei 404 (keine Wagenreihung bekannt).
    private func get(_ path: String, _ params: [String: String]) async throws -> Data? {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("de", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 || status == 204 { return nil }
        guard (200..<300).contains(status) else { throw TransitError.badResponse(status: status) }
        return data
    }
}

private actor EvaCache {
    static let shared = EvaCache()
    private var values: [String: String] = [:]
    func value(for key: String) -> String? { values[key] }
    func set(_ value: String, for key: String) { values[key] = value }
}

// MARK: - Antwortformate

enum DBDecoding {
    struct NearbyPlace: Decodable {
        let extId: String
        let products: [String]?
    }

    static func trainStation(from data: Data) throws -> String? {
        let places = try decode([NearbyPlace].self, data)
        let trains: Set<String> = ["ICE", "EC_IC", "IR", "REGIONAL", "SBAHN"]
        return places.first {
            $0.extId.count == 7 && $0.extId.hasPrefix("80") && !Set($0.products ?? []).isDisjoint(with: trains)
        }?.extId
    }

    struct VehicleSequence: Decodable {
        let departurePlatform: String?
        let platform: Platform?
        let groups: [Group]?

        struct Platform: Decodable {
            let start: Double?
            let end: Double?
            let sectors: [Sector]?
        }
        struct Sector: Decodable {
            let name: String
            let start: Double
            let end: Double
        }
        struct Group: Decodable {
            let transport: Transport?
            let vehicles: [Vehicle]
        }
        struct Transport: Decodable {
            let destination: Destination?
            struct Destination: Decodable { let name: String? }
        }
        struct Vehicle: Decodable {
            let amenities: [Amenity]?
            let platformPosition: Position
            let status: String?
            let type: VehicleType
            let wagonIdentificationNumber: Int?
        }
        struct Amenity: Decodable {
            let status: String?
            let type: String
        }
        struct Position: Decodable {
            let start: Double
            let end: Double
            let sector: String?
        }
        struct VehicleType: Decodable {
            let category: String
            let hasEconomyClass: Bool?
            let hasFirstClass: Bool?
        }
    }

    static func coachSequence(from data: Data) throws -> CoachSequence? {
        let raw = try decode(VehicleSequence.self, data)
        guard let groups = raw.groups, !groups.isEmpty else { return nil }
        var coaches: [CoachSequence.Coach] = []
        for (groupIndex, group) in groups.enumerated() {
            for vehicle in group.vehicles {
                let category = vehicle.type.category
                let available = Set((vehicle.amenities ?? []).filter { $0.status == "AVAILABLE" }.map(\.type))
                let kind: CoachSequence.Coach.Kind =
                    category == "LOCOMOTIVE" ? .locomotive
                    : category.hasPrefix("POWERCAR") ? .powerCar
                    : category.contains("CONTROLCAR") ? .controlCar
                    : .coach
                coaches.append(CoachSequence.Coach(
                    id: coaches.count,
                    number: vehicle.wagonIdentificationNumber.map(String.init),
                    kind: kind,
                    firstClass: vehicle.type.hasFirstClass ?? false,
                    secondClass: vehicle.type.hasEconomyClass ?? false,
                    doubleDeck: category.hasPrefix("DOUBLEDECK"),
                    dining: category.contains("DINING") || category.contains("RESTAURANT") || category.contains("BISTRO"),
                    closed: vehicle.status == "CLOSED",
                    start: vehicle.platformPosition.start,
                    end: vehicle.platformPosition.end,
                    sector: vehicle.platformPosition.sector,
                    bikes: available.contains("BIKE_SPACE"),
                    wheelchair: available.contains("WHEELCHAIR_SPACE"),
                    quietZone: available.contains("ZONE_QUIET"),
                    familyZone: available.contains("ZONE_FAMILY") || available.contains("CABIN_INFANT"),
                    group: groupIndex,
                    destination: group.transport?.destination?.name
                ))
            }
        }
        coaches.sort { $0.start < $1.start }
        for index in coaches.indices { coaches[index].id = index }
        return CoachSequence(
            platform: raw.departurePlatform,
            platformStart: raw.platform?.start ?? (coaches.first?.start ?? 0),
            platformEnd: raw.platform?.end ?? (coaches.last?.end ?? 0),
            sectors: (raw.platform?.sectors ?? []).map { .init(name: $0.name, start: $0.start, end: $0.end) },
            coaches: coaches
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw TransitError.decoding(String(describing: error)) }
    }
}

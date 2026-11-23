// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Datenquelle für den Verkehrsverbund Oberelbe (deckt DVB, RVSOE, S-Bahn Dresden usw. ab).
///
/// Nutzt die offene (inoffizielle) WebAPI `webapi.vvo-online.de`, siehe `docs/DATENQUELLEN.md`.
public struct VVOProvider: TransitProvider {
    public let id: ProviderID = .vvo

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "https://webapi.vvo-online.de")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: TransitProvider

    public func searchStops(query: String) async throws -> [Stop] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let body: [String: any Sendable] = ["query": trimmed, "limit": 15, "stopsOnly": true]
        let response: PointfinderResponse = try await post("tr/pointfinder", body: body)
        return response.stops
    }

    public func nearbyStops(around coordinate: Coordinate) async throws -> [Stop] {
        let gk = GaussKrueger.fromWGS84(coordinate)
        let body: [String: any Sendable] = [
            "query": "coord:\(Int(gk.easting.rounded())):\(Int(gk.northing.rounded()))",
            "assignedStops": true,
            "stopsOnly": false,
            "limit": 15,
        ]
        let response: PointfinderResponse = try await post("tr/pointfinder", body: body)
        return response.stops.sorted { ($0.distance ?? .max) < ($1.distance ?? .max) }
    }

    public func departures(at stop: Stop, limit: Int = 20) async throws -> [Departure] {
        let body: [String: any Sendable] = [
            "stopid": stop.stopID,
            "limit": limit,
            "shorttermchanges": true,
            "mentzonly": false,
        ]
        let response: DepartureMonitorResponse = try await post("dm", body: body)
        return response.departures
    }

    // MARK: HTTP

    func post<T: Decodable & StatusCarrying>(_ path: String, body: [String: any Sendable]) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TransitError.badResponse(status: http.statusCode)
        }
        return try VVODecoding.decode(T.self, from: data)
    }
}

// MARK: - Antwortformate

protocol StatusCarrying {
    var status: VVOStatus { get }
}

struct VVOStatus: Decodable {
    let code: String
    let message: String?

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case message = "Message"
    }
}

/// Dekodier-Helfer, auch von den Tests mit gespeicherten Antworten genutzt.
enum VVODecoding {
    static func decode<T: Decodable & StatusCarrying>(_ type: T.Type, from data: Data) throws -> T {
        let value: T
        do {
            value = try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Fehlerantworten enthalten oft nur den Status-Block.
            if let status = try? JSONDecoder().decode(StatusOnly.self, from: data), status.status.code != "Ok" {
                throw TransitError.service(message: status.status.message ?? status.status.code)
            }
            throw TransitError.decoding(String(describing: error))
        }
        guard value.status.code == "Ok" else {
            throw TransitError.service(message: value.status.message ?? value.status.code)
        }
        return value
    }

    /// Parst `"/Date(1795453020000-0000)/"` (Millisekunden seit 1970, Zeitzonen-Suffix ändert den Zeitpunkt nicht).
    static func parseDate(_ raw: String) -> Date? {
        guard let open = raw.firstIndex(of: "(") else { return nil }
        var digits = ""
        for ch in raw[raw.index(after: open)...] {
            if ch.isNumber || (digits.isEmpty && ch == "-") { digits.append(ch) } else { break }
        }
        guard let ms = Double(digits) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}

private struct StatusOnly: Decodable, StatusCarrying {
    let status: VVOStatus
    enum CodingKeys: String, CodingKey { case status = "Status" }
}

struct PointfinderResponse: Decodable, StatusCarrying {
    let status: VVOStatus
    let points: [String]

    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case points = "Points"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(VVOStatus.self, forKey: .status)
        points = try c.decodeIfPresent([String].self, forKey: .points) ?? []
    }

    /// Einträge haben das Format `ID|Typ|Ort|Name|Hochwert|Rechtswert|Entfernung|…`.
    /// Haltestellen haben eine rein numerische ID; Adressen/POIs werden übersprungen.
    var stops: [Stop] {
        points.compactMap { line in
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6, !f[0].isEmpty, f[0].allSatisfy(\.isNumber) else { return nil }
            var coordinate: Coordinate?
            if let n = Double(f[4]), let e = Double(f[5]), n > 0, e > 0 {
                coordinate = GaussKrueger.toWGS84(.init(easting: e, northing: n))
            }
            let distance = f.count > 6 ? Int(f[6]) : nil
            return Stop(provider: .vvo, stopID: f[0], name: f[3],
                        // Leerer Ort bedeutet bei der VVO-API „Dresden“.
                        place: f[2].isEmpty ? "Dresden" : f[2],
                        coordinate: coordinate,
                        distance: (distance ?? 0) > 0 ? distance : nil)
        }
    }
}

struct DepartureMonitorResponse: Decodable, StatusCarrying {
    let status: VVOStatus
    let raw: [RawDeparture]

    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case raw = "Departures"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(VVOStatus.self, forKey: .status)
        raw = try c.decodeIfPresent([RawDeparture].self, forKey: .raw) ?? []
    }

    var departures: [Departure] {
        raw.compactMap { $0.departure }.sorted { $0.expectedTime < $1.expectedTime }
    }

    struct RawDeparture: Decodable {
        let id: String
        let lineName: String
        let direction: String
        let platform: Platform?
        let mot: String?
        let realTime: String?
        let scheduledTime: String
        let state: String?
        let occupancy: String?

        struct Platform: Decodable {
            let name: String?
            enum CodingKeys: String, CodingKey { case name = "Name" }
        }

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case lineName = "LineName"
            case direction = "Direction"
            case platform = "Platform"
            case mot = "Mot"
            case realTime = "RealTime"
            case scheduledTime = "ScheduledTime"
            case state = "State"
            case occupancy = "Occupancy"
        }

        var departure: Departure? {
            guard let scheduled = VVODecoding.parseDate(scheduledTime) else { return nil }
            let real = realTime.flatMap(VVODecoding.parseDate)
            return Departure(
                // Die VVO-ID ist pro Fahrt eindeutig; Planzeit anhängen, falls dieselbe Linie mehrfach kommt.
                id: "\(id)@\(Int(scheduled.timeIntervalSince1970))",
                line: lineName,
                direction: direction,
                platform: platform?.name,
                mode: VVODecoding.mode(mot),
                scheduledTime: scheduled,
                realTime: real,
                state: Self.state(state, hasRealTime: real != nil),
                occupancy: Self.occupancy(occupancy),
                source: .vvo
            )
        }

        static func state(_ raw: String?, hasRealTime: Bool) -> DepartureState {
            switch raw {
            case "InTime": .onTime
            case "Delayed": .delayed
            case "Cancelled": .cancelled
            default: hasRealTime ? .onTime : .unknown
            }
        }

        static func occupancy(_ raw: String?) -> Occupancy {
            switch raw {
            case "ManySeats": .manySeats
            case "FewSeats": .fewSeats
            case "StandingOnly": .standingOnly
            case "Full": .full
            default: .unknown
            }
        }
    }
}

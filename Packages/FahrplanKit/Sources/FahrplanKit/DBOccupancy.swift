// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Auslastungsprognose der DB für Züge (2. Klasse), je Halt.
/// Ablauf: Bahnhof (EVA) am Einstieg → Abfahrtstafel → passende Fahrt (Linie + Plan-Abfahrt) → Fahrtverlauf.
public struct DBOccupancyProvider: Sendable {
    private let client: DBWebClient

    public init(session: URLSession = .shared) {
        client = DBWebClient(session: session)
    }

    public static func supports(_ leg: TripLeg) -> Bool {
        guard leg.kind == .ride, leg.stops.first?.coordinate != nil, leg.line != nil else { return false }
        return [.suburbanRailway, .train, .longDistance].contains(leg.mode ?? .other)
    }

    /// Fahrt mit der DB-Auslastung an ihren Halten (Halte ohne Angabe bleiben unverändert).
    /// Fehler und fehlende Daten liefern die Fahrt unverändert zurück.
    public func enrich(_ leg: TripLeg) async -> TripLeg {
        guard Self.supports(leg), let board = leg.stops.first, let coordinate = board.coordinate,
              let line = leg.line, let departure = (board.departure ?? board.arrival)?.scheduledTime
        else { return leg }
        do {
            guard let eva = try await client.evaNumber(near: coordinate) else { return leg }
            let key = "\(eva)|\(line)|\(Int(departure.timeIntervalSince1970))"
            let byName: [String: Occupancy]
            if let cached = await DBCache.shared.occupancy(for: key) {
                byName = cached
            } else {
                guard let journeyID = try await journeyID(eva: eva, line: line, departure: departure),
                      let data = try await client.get("reiseloesung/fahrt", ["journeyId": journeyID, "poly": "false"])
                else { return leg }
                byName = try DBDecoding.occupancyByStop(from: data)
                await DBCache.shared.setOccupancy(byName, for: key)
            }
            return Self.apply(byName, to: leg)
        } catch {
            return leg
        }
    }

    /// Fahrt in der Abfahrtstafel des Bahnhofs finden: gleiche Linie, gleiche Plan-Abfahrt (±1 min).
    private func journeyID(eva: String, line: String, departure: Date) async throws -> String? {
        let calendar = DBWebClient.berlin
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: departure)
        guard let data = try await client.get("reiseloesung/abfahrten", [
            "ortExtId": eva,
            "datum": String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0),
            "zeit": String(format: "%02d:%02d:00", c.hour ?? 0, c.minute ?? 0),
        ]) else { return nil }
        return try DBDecoding.journeyID(in: data, line: line, departure: departure)
    }

    /// Ordnet die Auslastung den Halten über den Namen zu (VVO/Transitous und DB schreiben Namen verschieden).
    static func apply(_ byName: [String: Occupancy], to leg: TripLeg) -> TripLeg {
        var result = leg
        for index in result.stops.indices where result.stops[index].occupancy == nil {
            let stop = result.stops[index]
            let candidates = [stop.place.map { "\($0) \(stop.name)" }, stop.name].compactMap { $0 }.map(DBDecoding.normalized)
            if let match = candidates.lazy.compactMap({ byName[$0] }).first {
                result.stops[index].occupancy = match
            } else if let match = byName.first(where: { key, _ in candidates.contains { key.hasPrefix($0) || $0.hasPrefix(key) } }) {
                result.stops[index].occupancy = match.value
            }
        }
        return result
    }
}

extension DBDecoding {
    struct Departures: Decodable {
        let entries: [Entry]
        struct Entry: Decodable {
            let zeit: String
            let journeyId: String
            let verkehrmittel: Vehicle
        }
        struct Vehicle: Decodable {
            let name: String?
            let linienNummer: String?
        }
    }

    static func journeyID(in data: Data, line: String, departure: Date) throws -> String? {
        let entries = try decode(Departures.self, data).entries
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let wanted = normalized(line)
        return entries.first { entry in
            guard let time = formatter.date(from: entry.zeit), abs(time.timeIntervalSince(departure)) < 90 else { return false }
            let names = [entry.verkehrmittel.linienNummer, entry.verkehrmittel.name].compactMap { $0 }.map(normalized)
            return names.contains(wanted)
        }?.journeyId
    }

    struct Journey: Decodable {
        let halte: [Stop]
        struct Stop: Decodable {
            let name: String
            let auslastungsmeldungen: [Load]?
        }
        struct Load: Decodable {
            let klasse: String
            let stufe: Int
        }
    }

    /// Normalisierter Haltname → Auslastung (2. Klasse; 1 gering … 4 außergewöhnlich hoch).
    static func occupancyByStop(from data: Data) throws -> [String: Occupancy] {
        var result: [String: Occupancy] = [:]
        for stop in try decode(Journey.self, data).halte {
            guard let load = stop.auslastungsmeldungen?.first(where: { $0.klasse == "KLASSE_2" }) else { continue }
            let occupancy: Occupancy? = switch load.stufe {
            case 1: .manySeats
            case 2: .fewSeats
            case 3: .standingOnly
            case 4: .full
            default: nil
            }
            if let occupancy { result[normalized(stop.name)] = occupancy }
        }
        return result
    }

    /// „Dresden Hbf“, „Dresden Hauptbahnhof“ und „Hauptbahnhof, Dresden“ vergleichbar machen.
    static func normalized(_ name: String) -> String {
        var s = name.lowercased()
            .replacingOccurrences(of: "hauptbahnhof", with: "hbf")
            .replacingOccurrences(of: "bahnhof", with: "")
            .replacingOccurrences(of: "s-bf.", with: "")
            .replacingOccurrences(of: "s-bahnhof", with: "")
        s = s.filter { $0.isLetter || $0.isNumber }
        return s
    }
}

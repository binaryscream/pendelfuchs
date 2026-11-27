// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Holt den aktuellen Stand einer gemerkten Fahrt – so sparsam wie möglich.
///
/// Statt bei jeder Prüfung (Benachrichtigungen, Live-Aktivität, Widget, „Meine Fahrten“) neu zu suchen, merkt
/// sich die App nach der ersten Suche des Tages die Kennung der passenden Verbindung und holt danach nur noch
/// genau diese ab (`refresh-itinerary`, auf Bitte von Transitous). Neu gesucht wird nur, wenn es keine Kennung
/// gibt (z. B. VVO-Daten), das Abholen scheitert oder die Verbindung gestört ist – dann braucht es ohnehin die
/// Suche, um einen Ersatz zu finden.
public enum SavedTripLookup {
    public struct Result: Sendable {
        /// Die gemerkte Verbindung, so wie sie laut Echtzeit fährt; `nil`, wenn sie nicht gefunden wurde.
        public var match: Trip?
        /// Was man nehmen sollte (bei Ausfall der Ersatz, siehe `SavedTrip.resolve`).
        public var resolved: SavedTrip.Resolved?
        /// `true`, wenn nur abgeholt statt neu gesucht wurde.
        public var refreshed: Bool
    }

    static let storageKey = "savedTrips.itineraryIDs.v1"
    static let lifetime: TimeInterval = 2 * 24 * 3600

    /// - Parameters:
    ///   - day: ein Zeitpunkt am Tag des Termins (die Uhrzeit wird durch die gemerkte Abfahrt ersetzt).
    ///   - suite: `UserDefaults`-Suite für die Kennungen (App Group, damit App und Widgets sie teilen). Als Name
    ///     statt als Objekt, weil `UserDefaults` nicht `Sendable` ist.
    public static func lookup(_ saved: SavedTrip, on day: Date, now: Date = .now,
                              using provider: any TransitProvider, suite: String?,
                              calendar: Calendar = .current) async throws -> Result {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let occurrence = saved.departure.date(on: day, calendar: calendar) ?? day
        let key = "\(saved.id.uuidString)|\(Int(occurrence.timeIntervalSince1970))"

        if let id = load(defaults, now: now)[key],
           let fresh = try? await provider.refresh(itineraryID: id, options: saved.options),
           fresh.disruption == nil, saved.bestMatch(in: [fresh], calendar: calendar) != nil {
            return Result(match: fresh, resolved: SavedTrip.Resolved(trip: fresh, note: nil), refreshed: true)
        }

        let trips = try await provider.trips(saved.query(on: occurrence, calendar: calendar))
        let match = saved.bestMatch(in: trips, calendar: calendar)
        var ids = load(defaults, now: now)
        ids[key] = match?.itineraryID
        save(ids, defaults)
        return Result(match: match, resolved: saved.resolve(in: trips, now: now, calendar: calendar), refreshed: false)
    }

    /// Gespeicherte Kennungen ohne die abgelaufenen (älter als zwei Tage).
    static func load(_ defaults: UserDefaults, now: Date) -> [String: String] {
        let all = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        return all.filter { key, _ in
            guard let seconds = key.split(separator: "|").last.flatMap({ Double($0) }) else { return false }
            return now.timeIntervalSince1970 - seconds < lifetime
        }
    }

    static func save(_ ids: [String: String], _ defaults: UserDefaults) {
        defaults.set(ids, forKey: storageKey)
    }
}

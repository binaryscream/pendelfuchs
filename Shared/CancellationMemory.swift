// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import Foundation

/// Merkt sich gesehene Ausfälle je Haltestelle (36 Stunden). Grund: Für vergangene Abfahrten liefert nur Transitous
/// Daten, und dort fehlen die Echtzeit-Ausfälle oft schon – ohne Gedächtnis sähe ein ausgefallener Zug später
/// wie ein normal abgefahrener aus.
enum CancellationMemory {
    private static let key = "memory.cancelledDepartures.v1"
    private static let lifetime: TimeInterval = 36 * 3600

    private struct Entry: Codable, Hashable {
        let stop: String
        let line: String
        let time: TimeInterval
    }

    private static func load() -> [Entry] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        let cutoff = Date.now.addingTimeInterval(-lifetime).timeIntervalSince1970
        return entries.filter { $0.time > cutoff }
    }

    private static func normalized(_ line: String) -> String {
        line.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Ausfälle aus `departures` speichern und bekannte Ausfälle auf die Liste anwenden.
    static func process(_ departures: [Departure], at stop: Stop) -> [Departure] {
        var entries = load()
        var known = Set(entries)
        for departure in departures where departure.state == .cancelled {
            let entry = Entry(stop: stop.id, line: normalized(departure.line), time: departure.scheduledTime.timeIntervalSince1970)
            if known.insert(entry).inserted { entries.append(entry) }
        }
        if let data = try? JSONEncoder().encode(Array(entries.suffix(800))) { AppGroup.defaults.set(data, forKey: key) }

        let here = entries.filter { $0.stop == stop.id }
        guard !here.isEmpty else { return departures }
        return departures.map { departure in
            guard departure.state != .cancelled else { return departure }
            let line = normalized(departure.line)
            let time = departure.scheduledTime.timeIntervalSince1970
            guard here.contains(where: { $0.line == line && abs($0.time - time) < 60 }) else { return departure }
            var copy = departure
            copy.state = .cancelled
            return copy
        }
    }
}

/// Einstellung „Ausgefallene Fahrten ausblenden“.
enum CancelledDisplay {
    static let hideKey = "display.hideCancelled"
    static var hide: Bool { AppGroup.defaults.bool(forKey: hideKey) }
}

extension Trip {
    /// Fällt ganz oder am Ein-/Ausstieg aus (nicht: nur verpasster Anschluss).
    var isCancelledForRider: Bool {
        switch disruption {
        case .rideCancelled, .boardingCancelled, .alightingCancelled: true
        default: false
        }
    }
}

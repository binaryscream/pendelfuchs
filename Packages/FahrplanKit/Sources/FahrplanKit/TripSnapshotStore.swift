// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Zuletzt geladener Stand gemerkter Fahrten – für die Anzeige ohne Netz (Tunnel, Funkloch).
///
/// Je Fahrt und Termin eine kleine JSON-Datei im angegebenen Ordner. Wird bei jeder erfolgreichen Abfrage
/// überschrieben; Dateien, deren Termin länger als zwei Tage zurückliegt, räumt `prune` weg.
public struct TripSnapshotStore: Sendable {
    public struct Snapshot: Codable, Sendable, Equatable {
        public var trip: Trip
        /// Hinweis, falls die App auf eine Ersatzverbindung umgeplant hat.
        public var note: String?
        public var fetchedAt: Date
    }

    public let directory: URL
    static let lifetime: TimeInterval = 2 * 24 * 3600

    public init(directory: URL) { self.directory = directory }

    private func url(_ id: UUID, _ occurrence: Date) -> URL {
        directory.appendingPathComponent("\(id.uuidString)-\(Int(occurrence.timeIntervalSince1970)).json")
    }

    public func save(_ trip: Trip, note: String?, for id: UUID, occurrence: Date, now: Date = .now) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Snapshot(trip: trip, note: note, fetchedAt: now)) else { return }
        try? data.write(to: url(id, occurrence), options: .atomic)
    }

    public func load(for id: UUID, occurrence: Date) -> Snapshot? {
        guard let data = try? Data(contentsOf: url(id, occurrence)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Entfernt Stände, deren Termin länger als zwei Tage vorbei ist.
    public func prune(now: Date = .now) {
        for file in files {
            guard let seconds = file.deletingPathExtension().lastPathComponent.split(separator: "-").last
                .flatMap({ Double($0) }), now.timeIntervalSince1970 - seconds > Self.lifetime else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Alles löschen (für „Daten zurücksetzen“).
    public func removeAll() {
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    private var files: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
    }
}

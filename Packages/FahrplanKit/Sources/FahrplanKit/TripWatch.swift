// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Worüber benachrichtigt werden kann.
public enum TripNoticeKind: String, Codable, Sendable, CaseIterable {
    /// Fahrt fällt aus, Ein- oder Ausstieg entfällt.
    case cancellation
    /// Abfahrt bzw. Ankunft verspätet sich.
    case delay
    /// Gleis- bzw. Steigwechsel beim Einstieg.
    case platformChange
    /// Anschluss verpasst oder sehr knapp.
    case connection
}

/// Eine Meldung, die verschickt werden soll.
public struct TripNotice: Sendable, Hashable {
    public var kind: TripNoticeKind
    public var title: String
    public var body: String
}

/// Einstellungen für die Benachrichtigungen.
public struct TripWatchSettings: Sendable, Hashable {
    public var enabledKinds: Set<TripNoticeKind>
    /// Ab so vielen Minuten Verspätung wird benachrichtigt.
    public var delayThreshold: Int
    /// Unter so vielen Minuten Umstiegszeit gilt ein Anschluss als knapp.
    public var tightConnectionMinutes: Int

    public init(enabledKinds: Set<TripNoticeKind> = Set(TripNoticeKind.allCases), delayThreshold: Int = 5,
                tightConnectionMinutes: Int = 2) {
        self.enabledKinds = enabledKinds
        self.delayThreshold = delayThreshold
        self.tightConnectionMinutes = tightConnectionMinutes
    }
}

/// Was zu einer Fahrt an einem Tag schon gemeldet wurde – damit dieselbe Meldung nicht bei jeder Abfrage kommt.
public struct TripWatchMemory: Codable, Sendable, Hashable {
    /// Zuletzt gemeldete Verspätung (Minuten), `nil` = keine gemeldet.
    public var notifiedDelay: Int?
    /// Zuletzt gemeldeter Ausfall bzw. Anschlussproblem (Schlüssel), `nil` = keins.
    public var notifiedDisruption: String?
    /// Gemeldete Gleiswechsel als „Fahrt:Gleis“.
    public var notifiedPlatforms: Set<String> = []
    /// Ein knapper Anschluss wurde gemeldet.
    public var notifiedTightConnection = false

    public init() {}
}

/// Erkennt, worüber zu einer gemerkten Fahrt benachrichtigt werden soll.
public enum TripWatch {
    /// Vergleicht den aktuellen Stand der Fahrt mit dem schon Gemeldeten.
    ///
    /// - Parameters:
    ///   - trip: die gemerkte Verbindung, so wie sie jetzt laut Echtzeit fährt (nicht der Ersatz).
    ///   - replacement: Ersatzverbindung des Verpass-Assistenten, falls es eine gibt.
    ///   - title: Name der gemerkten Fahrt („Zur Arbeit“), steht über jeder Meldung.
    /// - Returns: neue Meldungen und das aktualisierte Gedächtnis.
    public static func notices(for trip: Trip, replacement: Trip? = nil, title: String, now: Date,
                               memory: TripWatchMemory, settings: TripWatchSettings)
        -> (notices: [TripNotice], memory: TripWatchMemory) {
        var memory = memory
        var notices: [TripNotice] = []
        func add(_ kind: TripNoticeKind, _ body: String) {
            guard settings.enabledKinds.contains(kind) else { return }
            notices.append(TripNotice(kind: kind, title: title, body: body))
        }
        let replacementText = replacement.map { " Ersatz: \(summary(of: $0))." } ?? ""

        // Ausfall und verpasster Anschluss: einmal je Art (wechselt die Art, gibt es eine neue Meldung).
        let disruption = trip.disruption
        let disruptionKey = disruption.map(key(of:))
        if let disruption, disruptionKey != memory.notifiedDisruption {
            switch disruption {
            case .rideCancelled(let line):
                add(.cancellation, "\(line ?? "Eine Fahrt") fällt aus.\(replacementText)")
            case .boardingCancelled(let line, let stop):
                add(.cancellation, "\(line ?? "Fahrt"): Halt \(stop.name) entfällt – dort kein Einstieg.\(replacementText)")
            case .alightingCancelled(let line, let stop):
                add(.cancellation, "\(line ?? "Fahrt"): Halt \(stop.name) entfällt – dort kein Ausstieg.\(replacementText)")
            case .connectionMissed(let line, let stop):
                add(.connection, "\(line.map { "Anschluss \($0)" } ?? "Anschluss") in \(stop.name) ist nicht zu schaffen.\(replacementText)")
            }
        }
        memory.notifiedDisruption = disruptionKey
        // Bei Ausfall erübrigen sich Verspätung, Gleis und knapper Anschluss.
        guard disruption == nil else { return (notices, memory) }

        // Knapper Anschluss (aber noch zu schaffen).
        if let tight = tightConnection(in: trip, limit: settings.tightConnectionMinutes) {
            if !memory.notifiedTightConnection {
                let minutes = tight.minutes == 0 ? "keine Minute" : tight.minutes == 1 ? "nur 1 Minute" : "nur \(tight.minutes) Minuten"
                add(.connection, "\(tight.line.map { "Anschluss \($0)" } ?? "Anschluss") in \(tight.stop): \(minutes) zum Umsteigen.")
                memory.notifiedTightConnection = true
            }
        } else {
            memory.notifiedTightConnection = false
        }

        // Gleiswechsel beim Einstieg einer noch nicht abgefahrenen Fahrt.
        for (index, ride) in trip.rides.enumerated() {
            guard let stop = ride.stops.first, stop.platformChanged, let platform = stop.platform,
                  (ride.departure?.expectedTime ?? .distantPast) > now else { continue }
            let marker = "\(index):\(platform)"
            guard !memory.notifiedPlatforms.contains(marker) else { continue }
            memory.notifiedPlatforms.insert(marker)
            let word = [.train, .suburbanRailway, .longDistance].contains(ride.mode ?? .other) ? "Gleis" : "Steig"
            add(.platformChange, "\(ride.line ?? "Fahrt") in \(stop.name) heute von \(word) \(platform) "
                + "statt \(word) \(stop.scheduledPlatform ?? "?").")
        }

        // Verspätung: vor der Abfahrt die Abfahrt, danach die Ankunft. Erneut gemeldet, wenn sie sich um
        // mindestens 5 Minuten ändert – oder deutlich (2 Minuten) unter die Schwelle fällt. Der Abstand
        // verhindert, dass eine um die Schwelle pendelnde Verspätung immer neue Meldungen auslöst.
        let started = trip.departure.expectedTime <= now
        let point = started ? trip.arrival : trip.departure
        let delay = point.delayMinutes ?? 0
        if delay >= settings.delayThreshold {
            if memory.notifiedDelay == nil || abs(delay - (memory.notifiedDelay ?? 0)) >= 5 {
                let time = point.expectedTime.formatted(.dateTime.hour().minute())
                let what = started ? "Ankunft" : "Abfahrt \(trip.rides.first?.line ?? "")".trimmingCharacters(in: .whitespaces)
                add(.delay, "\(what) +\(delay) min, jetzt \(time).")
                memory.notifiedDelay = delay
            }
        } else if let notified = memory.notifiedDelay, delay <= max(settings.delayThreshold - 2, 0) {
            if !started {
                add(.delay, "Wieder fast pünktlich: Abfahrt \(trip.departure.expectedTime.formatted(.dateTime.hour().minute())) (statt +\(notified) min).")
            }
            memory.notifiedDelay = nil
        }
        return (notices, memory)
    }

    /// Erster Umstieg, bei dem weniger als `limit` Minuten bleiben (aber nicht verpasst).
    static func tightConnection(in trip: Trip, limit: Int) -> (line: String?, stop: String, minutes: Int)? {
        for (arriving, next) in zip(trip.rides, trip.rides.dropFirst()) {
            guard let arrival = arriving.arrival?.expectedTime, let departure = next.departure?.expectedTime,
                  let stop = next.stops.first else { continue }
            let buffer = departure.timeIntervalSince(arrival)
            if buffer >= 0, buffer < Double(limit) * 60 {
                return (next.line, stop.name, Int(buffer / 60))
            }
        }
        return nil
    }

    static func key(of disruption: TripDisruption) -> String {
        switch disruption {
        case .rideCancelled(let line): "cancelled:\(line ?? "")"
        case .boardingCancelled(let line, let stop): "boarding:\(line ?? ""):\(stop.stopID)"
        case .alightingCancelled(let line, let stop): "alighting:\(line ?? ""):\(stop.stopID)"
        case .connectionMissed(let line, let stop): "missed:\(line ?? ""):\(stop.stopID)"
        }
    }

    /// „7:42 mit S1, 7, an 8:20“
    static func summary(of trip: Trip) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute()
        let lines = trip.rides.map { $0.line ?? "?" }.joined(separator: ", ")
        return "\(trip.departure.expectedTime.formatted(style)) mit \(lines), an \(trip.arrival.expectedTime.formatted(style))"
    }
}

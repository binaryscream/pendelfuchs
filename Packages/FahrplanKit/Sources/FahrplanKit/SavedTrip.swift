// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Wochentag in deutscher Reihenfolge (Montag zuerst). Rohwert = `Calendar`-Wochentag (Sonntag = 1).
public enum Weekday: Int, Codable, Sendable, Hashable, CaseIterable, Identifiable, Comparable {
    case monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6, saturday = 7, sunday = 1

    public var id: Int { rawValue }

    public static let workdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let weekend: Set<Weekday> = [.saturday, .sunday]
    public static let everyDay: Set<Weekday> = Set(allCases)

    public init(date: Date, calendar: Calendar = .current) {
        self = Weekday(rawValue: calendar.component(.weekday, from: date))!
    }

    /// Position in der Woche, Montag = 0.
    public var index: Int { Weekday.allCases.firstIndex(of: self)! }

    public var shortName: String {
        switch self {
        case .monday: "Mo"
        case .tuesday: "Di"
        case .wednesday: "Mi"
        case .thursday: "Do"
        case .friday: "Fr"
        case .saturday: "Sa"
        case .sunday: "So"
        }
    }

    public var fullName: String {
        switch self {
        case .monday: "Montag"
        case .tuesday: "Dienstag"
        case .wednesday: "Mittwoch"
        case .thursday: "Donnerstag"
        case .friday: "Freitag"
        case .saturday: "Samstag"
        case .sunday: "Sonntag"
        }
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.index < rhs.index }
}

extension Set where Element == Weekday {
    /// Kurzbeschreibung, z. B. „Mo–Fr“, „Täglich“, „Sa, So“, „Mo, Mi–Fr“.
    public var summary: String {
        if isEmpty { return "Nicht regelmäßig" }
        if self == Weekday.everyDay { return "Täglich" }
        if self == Weekday.workdays { return "Mo–Fr" }
        if self == Weekday.weekend { return "Wochenende" }

        // Aufeinanderfolgende Tage zu Bereichen zusammenfassen (ab drei Tagen).
        var parts: [String] = []
        var run: [Weekday] = []
        func flush() {
            guard let first = run.first, let last = run.last else { return }
            if run.count >= 3 {
                parts.append("\(first.shortName)–\(last.shortName)")
            } else {
                parts.append(contentsOf: run.map(\.shortName))
            }
            run = []
        }
        for day in Weekday.allCases {
            if contains(day) { run.append(day) } else { flush() }
        }
        flush()
        return parts.joined(separator: ", ")
    }
}

/// Uhrzeit ohne Datum.
public struct TimeOfDay: Codable, Sendable, Hashable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    /// Diese Uhrzeit am Tag von `day`.
    public func date(on day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// Kürzester Abstand in Minuten (über Mitternacht hinweg).
    public func minutesApart(from other: TimeOfDay) -> Int {
        let d = abs(minutesSinceMidnight - other.minutesSinceMidnight)
        return min(d, 24 * 60 - d)
    }

    public var formatted: String { String(format: "%02d:%02d", hour, minute) }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutesSinceMidnight < rhs.minutesSinceMidnight }
}

/// Eine gemerkte Verbindung – optional regelmäßig an bestimmten Wochentagen.
public struct SavedTrip: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Eigener Name, z. B. „Zur Arbeit“.
    public var name: String?
    public var origin: Stop
    public var destination: Stop
    public var via: Stop?
    /// Geplante Abfahrt der gemerkten Verbindung.
    public var departure: TimeOfDay
    public var arrival: TimeOfDay?
    /// Linienfolge, z. B. `["S1", "7"]` – zum Wiederfinden der Verbindung.
    public var lines: [String]
    public var modes: [TransportMode]
    /// Leer = nur gemerkt, sonst regelmäßige Fahrt.
    public var weekdays: Set<Weekday>
    public var createdAt: Date
    /// Verpass-Assistent: bei Ausfall oder verpasstem Anschluss automatisch die nächste Verbindung nehmen.
    /// Optional gespeichert, damit ältere Daten lesbar bleiben; `nil` = eingeschaltet.
    public var rerouteAssistant: Bool?

    public var usesRerouteAssistant: Bool {
        get { rerouteAssistant ?? true }
        set { rerouteAssistant = newValue }
    }

    /// Benachrichtigungen zu dieser Fahrt (Ausfall, Verspätung …). Optional gespeichert, damit ältere Daten
    /// lesbar bleiben; `nil` = eingeschaltet.
    public var notifications: Bool?

    public var usesNotifications: Bool {
        get { notifications ?? true }
        set { notifications = newValue }
    }

    public init(trip: Trip, query: TripQuery, weekdays: Set<Weekday> = [], calendar: Calendar = .current) {
        func clean(_ stop: Stop) -> Stop { var s = stop; s.distance = nil; return s }
        id = UUID()
        name = nil
        origin = clean(query.origin)
        destination = clean(query.destination)
        via = query.via.map(clean)
        departure = TimeOfDay(date: trip.departure.scheduledTime, calendar: calendar)
        arrival = TimeOfDay(date: trip.arrival.scheduledTime, calendar: calendar)
        lines = trip.rides.map { $0.line ?? "?" }
        modes = trip.rides.map { $0.mode ?? .other }
        self.weekdays = weekdays
        createdAt = .now
    }

    public var isRegular: Bool { !weekdays.isEmpty }

    public var title: String { title(style: .withPlace) }

    public func title(style: StopNameStyle) -> String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return "\(origin.label(style)) → \(destination.label(style))"
    }

    /// Ist das genau diese Verbindung (gleiche Strecke, Abfahrt und Linien)?
    public func isSame(as trip: Trip, query: TripQuery, calendar: Calendar = .current) -> Bool {
        origin.id == query.origin.id && destination.id == query.destination.id && via?.id == query.via?.id
            && departure == TimeOfDay(date: trip.departure.scheduledTime, calendar: calendar)
            && lines == trip.rides.map { $0.line ?? "?" }
    }

    /// Nächster Termin der regelmäßigen Fahrt. Eine gerade abgefahrene Fahrt zählt noch
    /// `grace` lang als aktuell, damit man sie unterwegs weiter sieht.
    public func nextOccurrence(after now: Date = .now, grace: TimeInterval = 15 * 60,
                               calendar: Calendar = .current) -> Date? {
        guard isRegular else { return nil }
        let today = calendar.startOfDay(for: now)
        // Ab gestern: Eine Fahrt kurz vor Mitternacht zählt nach 0 Uhr noch `grace` lang als aktuell.
        for offset in -1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains(Weekday(date: day, calendar: calendar)),
                  let candidate = departure.date(on: day, calendar: calendar)
            else { continue }
            if candidate >= now.addingTimeInterval(-grace) { return candidate }
        }
        return nil
    }

    /// So viel früher als die gemerkte Abfahrt beginnt die Suche.
    public static let queryLead: TimeInterval = 5 * 60

    /// Suchanfrage, um die Verbindung an einem bestimmten Tag live abzufragen.
    public func query(on day: Date, calendar: Calendar = .current) -> TripQuery {
        // Ein paar Minuten früher fragen: `departure` ist die Abfahrt der ersten Bahn. Beginnt die Verbindung mit
        // einem Fußweg oder wurde der Fahrplan um eine Minute vorgezogen, fehlte sie sonst im Ergebnis.
        let time = (departure.date(on: day, calendar: calendar) ?? day).addingTimeInterval(-Self.queryLead)
        return TripQuery(origin: origin, destination: destination, via: via, time: time, isArrivalTime: false)
    }

    /// Ergebnis von `resolve`: die Verbindung, die man jetzt nehmen sollte, und ein Hinweis, falls sie die
    /// gemerkte ersetzt (Ausfall, verpasster Anschluss).
    public struct Resolved: Sendable {
        public var trip: Trip
        public var note: String?
    }

    /// Wie `bestMatch`, aber mit Ersatz: Ist die gemerkte Verbindung nicht fahrbar (Fahrt fällt aus, Halt entfällt,
    /// Anschluss verpasst), wird die nächste fahrbare genommen – bevorzugt mit derselben ersten Fahrt
    /// (man sitzt ja schon im Bus), sonst die nächste Abfahrt, solange man noch nicht losgefahren ist.
    public func resolve(in trips: [Trip], now: Date = .now, calendar: Calendar = .current) -> Resolved? {
        guard let match = bestMatch(in: trips, calendar: calendar) else { return nil }
        guard let problem = match.disruption, usesRerouteAssistant else { return Resolved(trip: match, note: nil) }

        let usable = trips.filter { $0.disruption == nil }
        let first = match.rides.first
        // Eine ausgefallene erste Fahrt (oder ein entfallener Einstieg) hat man nicht angetreten – dann gilt
        // der Ersatz auch nach der geplanten Abfahrtszeit weiter.
        let started = first?.isUnusable != true && (first?.departure?.expectedTime ?? .distantFuture) <= now

        var replacement = usable
            .filter { $0.rides.first?.line == first?.line
                && $0.rides.first?.departure?.scheduledTime == first?.departure?.scheduledTime }
            .min { $0.arrival.expectedTime < $1.arrival.expectedTime }
        if replacement == nil, !started {
            replacement = usable
                .filter { $0.departure.expectedTime > match.departure.expectedTime }
                .min { $0.departure.expectedTime < $1.departure.expectedTime }
        }
        guard let replacement else { return Resolved(trip: match, note: nil) }
        return Resolved(trip: replacement, note: problem.rerouteNote)
    }

    /// Findet die gemerkte Verbindung in frischen Suchergebnissen wieder.
    /// Erst exakt (gleiche Linien, ±2 min), sonst die nächstgelegene mit gleicher erster Linie (±10 min),
    /// damit kleine Fahrplanänderungen nicht gleich zum Verlust führen.
    public func bestMatch(in trips: [Trip], calendar: Calendar = .current) -> Trip? {
        func minutes(_ trip: Trip) -> Int {
            TimeOfDay(date: trip.departure.scheduledTime, calendar: calendar).minutesApart(from: departure)
        }
        if let exact = trips.first(where: { $0.rides.map { $0.line ?? "?" } == lines && minutes($0) <= 2 }) {
            return exact
        }
        return trips
            .filter { $0.rides.first?.line == lines.first && minutes($0) <= 10 }
            .min { minutes($0) < minutes($1) }
    }
}

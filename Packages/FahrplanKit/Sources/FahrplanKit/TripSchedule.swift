// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Bundesland – für die gesetzlichen Feiertage, an denen regelmäßige Fahrten aussetzen.
public enum FederalState: String, CaseIterable, Sendable, Codable {
    case sh, hh, ni, hb, nw, he, rp, bw, by, sl, be, bb, mv, sn, st, th

    /// Aus den ersten zwei Stellen des amtlichen Kreisschlüssels (`14628` → Sachsen).
    public init?(district: String) {
        let codes: [String: FederalState] = [
            "01": .sh, "02": .hh, "03": .ni, "04": .hb, "05": .nw, "06": .he, "07": .rp, "08": .bw,
            "09": .by, "10": .sl, "11": .be, "12": .bb, "13": .mv, "14": .sn, "15": .st, "16": .th,
        ]
        guard let state = codes[String(district.prefix(2))] else { return nil }
        self = state
    }

    /// Bundesland einer Haltestelle: aus der bundesweiten Haltestellen-ID, sonst aus dem Verbund der Quelle.
    /// `nil`, wenn es sich nicht bestimmen lässt (dann zählen nur die bundesweiten Feiertage).
    public static func of(_ stop: Stop) -> FederalState? {
        if let district = DHID(transitousID: stop.stopID)?.district, let state = FederalState(district: district) {
            return state
        }
        if stop.provider == .vvo { return .sn }
        switch stop.provider.regionalNetwork {
        case .vms, .vvv: return .sn
        case .bayern: return .by
        case .nvbw: return .bw
        case .nrw: return .nw
        case .vmv: return .mv
        case nil: return nil
        }
    }

    public var name: String {
        switch self {
        case .sh: "Schleswig-Holstein"
        case .hh: "Hamburg"
        case .ni: "Niedersachsen"
        case .hb: "Bremen"
        case .nw: "Nordrhein-Westfalen"
        case .he: "Hessen"
        case .rp: "Rheinland-Pfalz"
        case .bw: "Baden-Württemberg"
        case .by: "Bayern"
        case .sl: "Saarland"
        case .be: "Berlin"
        case .bb: "Brandenburg"
        case .mv: "Mecklenburg-Vorpommern"
        case .sn: "Sachsen"
        case .st: "Sachsen-Anhalt"
        case .th: "Thüringen"
        }
    }
}

/// Gesetzliche Feiertage in Deutschland, auf dem Gerät berechnet.
///
/// Nur Feiertage, die im **ganzen** Bundesland gelten. Nicht dabei sind Feiertage einzelner Gemeinden
/// (Fronleichnam in Teilen Sachsens und Thüringens, Mariä Himmelfahrt in Teilen Bayerns, Augsburger Friedensfest).
public enum Holidays {
    /// Name des Feiertags an diesem Tag, sonst `nil`. Ohne Bundesland zählen nur die bundesweiten.
    public static func name(on day: Date, in state: FederalState?, calendar: Calendar = .current) -> String? {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else { return nil }

        func isIn(_ states: FederalState...) -> Bool { state.map(states.contains) ?? false }

        switch (month, dayOfMonth) {
        case (1, 1): return "Neujahr"
        case (1, 6) where isIn(.bw, .by, .st): return "Heilige Drei Könige"
        case (3, 8) where isIn(.be, .mv): return "Internationaler Frauentag"
        case (5, 1): return "Tag der Arbeit"
        case (8, 15) where isIn(.sl): return "Mariä Himmelfahrt"
        case (9, 20) where isIn(.th): return "Weltkindertag"
        case (10, 3): return "Tag der Deutschen Einheit"
        case (10, 31) where isIn(.bb, .hb, .hh, .mv, .ni, .sn, .st, .sh, .th): return "Reformationstag"
        case (11, 1) where isIn(.bw, .by, .nw, .rp, .sl): return "Allerheiligen"
        case (12, 25): return "1. Weihnachtstag"
        case (12, 26): return "2. Weihnachtstag"
        default: break
        }

        // Bewegliche Feiertage, gerechnet in Tagen ab Ostersonntag.
        let utc = gregorianUTC
        guard let easter = easterSunday(year: year),
              let today = utc.date(from: DateComponents(year: year, month: month, day: dayOfMonth)),
              let offset = utc.dateComponents([.day], from: easter, to: today).day
        else { return nil }
        switch offset {
        case -2: return "Karfreitag"
        case 1: return "Ostermontag"
        case 39: return "Christi Himmelfahrt"
        case 50: return "Pfingstmontag"
        case 60 where isIn(.bw, .by, .he, .nw, .rp, .sl): return "Fronleichnam"
        default: break
        }

        // Buß- und Bettag (nur Sachsen): der Mittwoch vor dem 23. November.
        if isIn(.sn), month == 11, (16...22).contains(dayOfMonth), utc.component(.weekday, from: today) == 4 {
            return "Buß- und Bettag"
        }
        return nil
    }

    /// Die nächsten Feiertage ab `day` (einschließlich), höchstens `limit` Stück innerhalb eines Jahres.
    public static func upcoming(from day: Date, in state: FederalState?, limit: Int = 20,
                                calendar: Calendar = .current) -> [(day: Date, name: String)] {
        let start = calendar.startOfDay(for: day)
        var result: [(day: Date, name: String)] = []
        for offset in 0...366 where result.count < limit {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start),
                  let name = name(on: candidate, in: state, calendar: calendar) else { continue }
            result.append((candidate, name))
        }
        return result
    }

    /// Ostersonntag (gregorianisch, Verfahren nach Meeus/Jones/Butcher), als Mitternacht UTC.
    static func easterSunday(year: Int) -> Date? {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return gregorianUTC.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

/// Wann regelmäßige Fahrten aussetzen: an Feiertagen und während einer Pause (Urlaub).
///
/// Gilt für alles, was den nächsten Termin einer regelmäßigen Fahrt braucht – Übersicht, Erinnerungen,
/// Benachrichtigungen, Widgets, Siri. Die Einstellung liegt in den gemeinsamen `UserDefaults` der App-Gruppe,
/// damit App und Widgets dasselbe sehen.
public struct TripSchedule: Sendable, Equatable {
    /// An gesetzlichen Feiertagen aussetzen.
    public var skipHolidays: Bool
    /// Fest gewähltes Bundesland für die Feiertage; `nil` = automatisch nach der Starthaltestelle der Fahrt.
    public var state: FederalState?
    /// Pause von … bis einschließlich … (jeweils ganze Tage).
    public var pause: ClosedRange<Date>?

    public init(skipHolidays: Bool = true, state: FederalState? = nil, pause: ClosedRange<Date>? = nil) {
        self.skipHolidays = skipHolidays
        self.state = state
        self.pause = pause
    }

    /// Nichts aussetzen.
    public static let none = TripSchedule(skipHolidays: false)

    public enum SkipReason: Sendable, Equatable {
        /// Pause bis einschließlich dieses Tages.
        case paused(until: Date)
        case holiday(String)
    }

    /// Warum eine regelmäßige Fahrt ab `origin` an diesem Tag aussetzt – `nil`, wenn sie fährt.
    public func skipReason(on day: Date, origin: Stop, calendar: Calendar = .current) -> SkipReason? {
        if let pause, covers(day, in: pause, calendar: calendar) { return .paused(until: pause.upperBound) }
        if skipHolidays, let name = Holidays.name(on: day, in: holidayState(for: origin), calendar: calendar) {
            return .holiday(name)
        }
        return nil
    }

    /// Bundesland, dessen Feiertage für eine Fahrt ab `origin` gelten: das gewählte, sonst das der Haltestelle.
    public func holidayState(for origin: Stop) -> FederalState? { state ?? FederalState.of(origin) }

    /// Läuft die Pause an diesem Tag (oder beginnt sie später noch)?
    public func activePause(on day: Date, calendar: Calendar = .current) -> ClosedRange<Date>? {
        guard let pause, calendar.startOfDay(for: day) <= calendar.startOfDay(for: pause.upperBound) else { return nil }
        return pause
    }

    private func covers(_ day: Date, in pause: ClosedRange<Date>, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        return start >= calendar.startOfDay(for: pause.lowerBound) && start <= calendar.startOfDay(for: pause.upperBound)
    }

    // MARK: Speicherung

    public static let suiteName = "group.de.pendelfuchs.app"
    public static let skipHolidaysKey = "schedule.skipHolidays"
    /// Kürzel des gewählten Bundeslands; leer oder fehlend = automatisch.
    public static let stateKey = "schedule.state"
    public static let pauseFromKey = "schedule.pauseFrom"
    public static let pauseUntilKey = "schedule.pauseUntil"

    /// Die gespeicherte Einstellung (App-Gruppe). Ohne gespeicherte Werte: Feiertage aussetzen, keine Pause.
    public static var current: TripSchedule { load(from: UserDefaults(suiteName: suiteName) ?? .standard) }

    public static func load(from defaults: UserDefaults) -> TripSchedule {
        var schedule = TripSchedule(skipHolidays: defaults.object(forKey: skipHolidaysKey) as? Bool ?? true,
                                    state: defaults.string(forKey: stateKey).flatMap(FederalState.init(rawValue:)))
        if let from = defaults.object(forKey: pauseFromKey) as? Double,
           let until = defaults.object(forKey: pauseUntilKey) as? Double, until > 0, from <= until {
            schedule.pause = Date(timeIntervalSince1970: from)...Date(timeIntervalSince1970: until)
        }
        return schedule
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(skipHolidays, forKey: Self.skipHolidaysKey)
        defaults.set(state?.rawValue ?? "", forKey: Self.stateKey)
        if let pause {
            defaults.set(pause.lowerBound.timeIntervalSince1970, forKey: Self.pauseFromKey)
            defaults.set(pause.upperBound.timeIntervalSince1970, forKey: Self.pauseUntilKey)
        } else {
            defaults.removeObject(forKey: Self.pauseFromKey)
            defaults.removeObject(forKey: Self.pauseUntilKey)
        }
    }
}

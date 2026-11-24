// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Zustand des „Tauschen“-Knopfs im Strecken-Widget: gilt nur für einen Tagesabschnitt (vor/nach der Wendezeit),
/// danach gilt wieder die automatische Richtung.
public struct RouteSwapState: Codable, Sendable, Hashable {
    public var periodID: String
    public var swapped: Bool

    public init(periodID: String, swapped: Bool) {
        self.periodID = periodID
        self.swapped = swapped
    }
}

/// Richtung eines Strecken-Widgets (Hin- oder Rückweg).
///
/// - Vor der Wendezeit (z. B. 14:00) zeigt das Widget A → B, ab der Wendezeit den Rückweg B → A.
/// - Der Knopf „Tauschen“ dreht die Richtung bis zum nächsten Abschnitt (Wendezeit bzw. Mitternacht) um.
public enum RouteDirection {
    /// Kennung des Tagesabschnitts, z. B. `2026-11-24|vor` bzw. `2026-11-24|nach`.
    public static func periodID(at date: Date, turnAt: TimeOfDay?, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return "\(day)|\(isAfterTurn(date, turnAt: turnAt, calendar: calendar) ? "nach" : "vor")"
    }

    public static func isAfterTurn(_ date: Date, turnAt: TimeOfDay?, calendar: Calendar = .current) -> Bool {
        guard let turnAt else { return false }
        return TimeOfDay(date: date, calendar: calendar) >= turnAt
    }

    /// `true`, wenn der Rückweg (Ziel → Start) gezeigt werden soll.
    public static func isReversed(at date: Date, turnAt: TimeOfDay?, state: RouteSwapState?,
                                  calendar: Calendar = .current) -> Bool {
        let automatic = isAfterTurn(date, turnAt: turnAt, calendar: calendar)
        let period = periodID(at: date, turnAt: turnAt, calendar: calendar)
        let swapped = state?.periodID == period ? (state?.swapped ?? false) : false
        return automatic != swapped
    }

    /// Neuer Zustand nach Druck auf „Tauschen“.
    public static func toggled(at date: Date, turnAt: TimeOfDay?, state: RouteSwapState?,
                               calendar: Calendar = .current) -> RouteSwapState {
        let period = periodID(at: date, turnAt: turnAt, calendar: calendar)
        let current = state?.periodID == period ? (state?.swapped ?? false) : false
        return RouteSwapState(periodID: period, swapped: !current)
    }

    /// Nächster Zeitpunkt, an dem sich die automatische Richtung ändert (Wendezeit oder Mitternacht).
    public static func nextChange(after date: Date, turnAt: TimeOfDay?, calendar: Calendar = .current) -> Date {
        var candidates: [Date] = []
        if let turnAt, let today = turnAt.date(on: date, calendar: calendar), today > date { candidates.append(today) }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) {
            candidates.append(midnight)
        }
        return candidates.min() ?? date.addingTimeInterval(86_400)
    }
}

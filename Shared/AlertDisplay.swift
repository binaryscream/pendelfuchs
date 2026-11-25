// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import Foundation

/// Welche Störungs-/Baustellenhinweise gezeigt werden (Einstellung).
enum AlertDisplay: String, CaseIterable, Identifiable {
    case off, affected, all

    static let storageKey = "display.alerts"
    var id: String { rawValue }

    static var current: AlertDisplay {
        AppGroup.defaults.string(forKey: storageKey).flatMap(AlertDisplay.init(rawValue:)) ?? .affected
    }

    var title: String {
        switch self {
        case .off: "Aus"
        case .affected: "Nur für meinen Abschnitt"
        case .all: "Alle zur Linie"
        }
    }

    /// Hinweise, die für die genannten Halte gezeigt werden.
    func filter(_ alerts: [ServiceAlert], names: [String]) -> [ServiceAlert] {
        switch self {
        case .off: []
        case .all: alerts
        case .affected: alerts.filter { $0.mentions(anyOf: names) }
        }
    }

    func filter(_ leg: TripLeg) -> [ServiceAlert] { filter(leg.alerts, names: leg.stopNames) }

    func filter(_ trip: Trip) -> [ServiceAlert] {
        var seen = Set<String>()
        return trip.rides.flatMap(filter).filter { seen.insert($0.id).inserted }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Wie Verspätungen dargestellt werden. Die Einstellung liegt in der App Group, damit Widgets sie ebenfalls nutzen.
enum DelayDisplay: String, CaseIterable, Identifiable {
    /// Geplante Zeit mit Zusatz: „06:23 +2“
    case badge
    /// Nur die tatsächliche Zeit (Verspätung eingerechnet): „06:25“
    case actual
    /// Geplante Zeit oben, darunter die tatsächliche: „06:23“ / „06:25“
    case both

    static let storageKey = "display.delay"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .badge: "Plan mit Zusatz"
        case .actual: "Tatsächliche Zeit"
        case .both: "Plan und tatsächlich"
        }
    }

    var example: String {
        switch self {
        case .badge: "06:23 +2"
        case .actual: "06:25"
        case .both: "06:23 · 06:25"
        }
    }

    static var current: DelayDisplay {
        AppGroup.defaults.string(forKey: storageKey).flatMap(DelayDisplay.init(rawValue:)) ?? .badge
    }
}

/// Uhrzeit mit Verspätung in der gewählten Darstellung (siehe `DelayDisplay`).
/// Schriftart und -gewicht kommen vom umgebenden `.font(...)`.
struct DelayedTimeText: View {
    let scheduled: Date
    /// Echtzeit-Prognose; `nil`, wenn keine vorliegt.
    var actual: Date?
    /// Geplante und tatsächliche Zeit nebeneinander statt untereinander (für Widgets mit festem Platz).
    var inline = false

    @AppStorage(DelayDisplay.storageKey, store: AppGroup.defaults) private var style = DelayDisplay.badge

    private var delay: Int {
        guard let actual else { return 0 }
        return Int((actual.timeIntervalSince(scheduled) / 60).rounded())
    }

    private var delayColor: Color { delay >= 3 ? .red : .orange }

    var body: some View {
        Group {
            if delay == 0 {
                time(scheduled)
            } else {
                switch style {
                case .badge:
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        time(scheduled)
                        Text(delay > 0 ? "+\(delay)" : "\(delay)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(delayColor)
                    }
                case .actual:
                    time(actual ?? scheduled).foregroundStyle(delayColor)
                case .both:
                    if inline {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            time(scheduled)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .strikethrough(true, color: .secondary)
                            time(actual ?? scheduled).foregroundStyle(delayColor)
                        }
                        .lineLimit(1)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            time(scheduled)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .strikethrough(true, color: .secondary)
                            time(actual ?? scheduled).foregroundStyle(delayColor)
                        }
                    }
                }
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func time(_ date: Date) -> Text {
        Text(date, format: .dateTime.hour().minute())
    }

    private var accessibilityText: String {
        let planned = scheduled.formatted(date: .omitted, time: .shortened)
        if delay > 0 { return "\(planned), \(delay) Minuten verspätet" }
        if delay < 0 { return "\(planned), \(-delay) Minuten früher" }
        return planned
    }
}

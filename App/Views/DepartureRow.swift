// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

struct DepartureRow: View {
    let departure: Departure
    let now: Date

    private var cancelled: Bool { departure.state == .cancelled }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LineBadge(line: departure.line, mode: departure.mode)

            VStack(alignment: .leading, spacing: 3) {
                Text(departure.direction)
                    .font(.body.weight(.medium))
                    .strikethrough(cancelled)
                    .lineLimit(1)
                details
            }

            Spacer(minLength: 8)

            countdown
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var details: some View {
        HStack(spacing: 6) {
            if cancelled {
                Text("Fällt aus").foregroundStyle(.red).fontWeight(.semibold)
            } else {
                Text(departure.scheduledTime, format: .dateTime.hour().minute())
                if let delay = departure.delayMinutes, delay != 0 {
                    Text(delay > 0 ? "+\(delay)" : "\(delay)")
                        .foregroundStyle(delay >= 3 ? .red : .orange)
                        .fontWeight(.semibold)
                } else if !departure.hasRealTime {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .accessibilityLabel("Keine Echtzeitdaten")
                }
            }
            if let platform = departure.platform, !platform.isEmpty {
                Text("·")
                Text(departure.mode == .train || departure.mode == .suburbanRailway ? "Gl. \(platform)" : "Steig \(platform)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    @ViewBuilder private var countdown: some View {
        let minutes = departure.minutesUntilDeparture(from: now)
        Group {
            if cancelled {
                Text("–")
            } else if minutes == 0 {
                Text("jetzt")
            } else if minutes < 60 {
                Text("\(minutes) min")
            } else {
                Text(departure.expectedTime, format: .dateTime.hour().minute())
            }
        }
        .font(.title3.weight(.semibold).monospacedDigit())
        .foregroundStyle(departure.hasRealTime && !cancelled ? Color.primary : Color.secondary)
    }
}

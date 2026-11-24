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
                    .minimumScaleFactor(0.8)
                details
            }

            Spacer(minLength: 8)

            countdown
        }
        .padding(.vertical, 2)
        .opacity(departed ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    /// Schon abgefahren (mit etwas Toleranz, damit „jetzt“ nicht sofort ausgegraut wird).
    private var departed: Bool { departure.expectedTime < now.addingTimeInterval(-45) }

    @ViewBuilder private var details: some View {
        HStack(spacing: 6) {
            if cancelled {
                Text("Fällt aus").foregroundStyle(.red).fontWeight(.semibold)
            } else {
                DelayedTimeText(scheduled: departure.scheduledTime, actual: departure.realTime)
                if !departure.hasRealTime {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .accessibilityLabel("Keine Echtzeitdaten")
                }
            }
            if let platform = departure.platform, !platform.isEmpty {
                Text("·")
                Text(departure.mode.platformLabel(platform))
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
            } else if departed {
                Text(departure.expectedTime, format: .dateTime.hour().minute())
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

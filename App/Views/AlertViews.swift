// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Störungs-/Baustellenhinweis zum Aufklappen.
struct AlertRow: View {
    let alert: ServiceAlert
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(alert.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(expanded ? nil : 2)
                    Spacer(minLength: 4)
                    if alert.text != nil || alert.url != nil {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                if let text = alert.text {
                    Text(text).font(.footnote).foregroundStyle(.secondary)
                }
                if let until = alert.validUntil, until.timeIntervalSinceNow < 400 * 86_400 {
                    Text("Gilt bis \(until.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let url = alert.url {
                    Link("Mehr dazu", destination: url).font(.footnote)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// „Gl. 3 statt 1“ – bei Gleiswechsel orange und fett, sonst normal.
struct PlatformText: View {
    let platform: String
    var scheduled: String?
    let mode: TransportMode

    var body: some View {
        if let scheduled, scheduled != platform {
            Text("\(mode.platformLabel(platform)) statt \(scheduled)")
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
                .accessibilityLabel("Gleiswechsel: \(mode.platformLabel(platform)) statt \(scheduled)")
        } else {
            Text(mode.platformLabel(platform))
        }
    }
}

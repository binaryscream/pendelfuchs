// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

extension Occupancy {
    var title: String {
        switch self {
        case .manySeats: "Viele Plätze frei"
        case .fewSeats: "Wenige Plätze frei"
        case .standingOnly: "Nur Stehplätze"
        case .full: "Voll"
        case .unknown: "Auslastung unbekannt"
        }
    }

    /// Belegte Figuren von dreien.
    var level: Int {
        switch self {
        case .manySeats: 1
        case .fewSeats: 2
        case .standingOnly, .full: 3
        case .unknown: 0
        }
    }

    var color: Color {
        switch self {
        case .manySeats: .green
        case .fewSeats: .orange
        case .standingOnly, .full: .red
        case .unknown: .secondary
        }
    }
}

/// Auslastung als drei kleine Figuren (gefüllt = belegt), optional mit Text.
struct OccupancyView: View {
    let occupancy: Occupancy
    var showsTitle = false

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "person.fill")
                        .foregroundStyle(index < occupancy.level ? AnyShapeStyle(occupancy.color) : AnyShapeStyle(.quaternary))
                }
            }
            .imageScale(.small)
            if showsTitle {
                Text(occupancy.title).foregroundStyle(occupancy.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(occupancy.title)
    }
}

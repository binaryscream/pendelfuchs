// SPDX-License-Identifier: GPL-3.0-or-later
// Gemeinsam genutzt von App und Widget-Erweiterung (Live-Aktivität, Widgets).

import FahrplanKit
import SwiftUI

/// Liniennummer als farbiges Kästchen, Farbe je Verkehrsmittel.
struct LineBadge: View {
    let line: String
    let mode: TransportMode
    /// Kleine Variante für die Verbindungsübersicht.
    var compact = false

    var body: some View {
        let height: CGFloat = compact ? 22 : 30
        Text(line)
            .font(.system(compact ? .caption : .subheadline, design: .rounded).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 6 : 0)
            .frame(minWidth: compact ? 30 : 48, maxWidth: compact ? 64 : 48, minHeight: height, maxHeight: height)
            .background(mode.color, in: RoundedRectangle(cornerRadius: mode == .tram ? 5 : height / 2))
            .accessibilityLabel("\(mode.displayName) \(line)")
    }
}

extension TransportMode {
    /// Linienfarbe mit eigener Variante für den Dark Mode (dunkle Farben werden dort aufgehellt,
    /// damit sie sich von den dunklen Listenzeilen abheben; weiße Schrift bleibt gut lesbar).
    var color: Color {
        switch self {
        case .tram: Color(light: (0.84, 0.10, 0.13), dark: (0.90, 0.20, 0.22))
        case .cityBus: Color(light: (0.05, 0.40, 0.70), dark: (0.15, 0.48, 0.80))
        case .regionalBus: Color(light: (0.45, 0.20, 0.55), dark: (0.58, 0.32, 0.68))
        case .suburbanRailway: Color(light: (0.00, 0.55, 0.30), dark: (0.05, 0.58, 0.34))
        case .train: Color(light: (0.25, 0.25, 0.30), dark: (0.46, 0.46, 0.53))
        case .ferry: Color(light: (0.00, 0.60, 0.75), dark: (0.05, 0.55, 0.70))
        case .cableway: Color(light: (0.55, 0.35, 0.15), dark: (0.65, 0.45, 0.25))
        case .onDemand: Color(light: (0.85, 0.50, 0.00), dark: (0.80, 0.48, 0.05))
        case .subway: Color(light: (0.00, 0.30, 0.60), dark: (0.10, 0.42, 0.75))
        case .other: Color(light: (0.50, 0.50, 0.53), dark: (0.50, 0.50, 0.55))
        }
    }
}

extension Color {
    /// Farbe, die sich automatisch an Hell/Dunkel anpasst.
    init(light: (Double, Double, Double), dark: (Double, Double, Double)) {
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

extension TransportMode {
    /// Schienenverkehr mit „Gleis“ statt „Steig“.
    var usesTracks: Bool { self == .train || self == .suburbanRailway }

    /// „Gl. 1“ bzw. „Steig 4“.
    func platformLabel(_ platform: String) -> String {
        usesTracks ? "Gl. \(platform)" : "Steig \(platform)"
    }
}

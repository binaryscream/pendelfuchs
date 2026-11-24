// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

extension StopNameStyle {
    static let storageKey = "display.stopName"

    /// Gewählte Darstellung (für Widgets und Live-Aktivitäten, die nicht über die SwiftUI-Umgebung versorgt werden).
    static var current: StopNameStyle {
        AppGroup.defaults.string(forKey: storageKey).flatMap(StopNameStyle.init(rawValue:)) ?? .withPlace
    }
}

extension EnvironmentValues {
    /// Darstellung der Haltestellennamen in der App (siehe Einstellungen).
    @Entry var stopNameStyle: StopNameStyle = .withPlace
}

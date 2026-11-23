// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import Foundation

/// Welche Datenquellen App, Widget und Live-Aktivität verwenden (Einstellung in der App Group).
enum DataSources {
    /// Ob im VVO-Gebiet zusätzlich die VVO-WebAPI genutzt wird (Preise, Auslastung).
    static let useVVOKey = "dataSources.useVVO"

    static var useVVO: Bool {
        AppGroup.defaults.object(forKey: useVVOKey) as? Bool ?? true
    }

    static func router(useVVO: Bool = DataSources.useVVO) -> ProviderRouter {
        ProviderRouter(vvo: useVVO ? VVOProvider() : nil)
    }

    /// Pflicht-Quellenangabe von Transitous.
    static let transitousSourcesURL = URL(string: "https://transitous.org/sources/")!
    static let openStreetMapURL = URL(string: "https://www.openstreetmap.org/copyright")!
}

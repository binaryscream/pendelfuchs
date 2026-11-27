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

    /// Ob in Sachsen, Bayern, Baden-Württemberg, NRW und Mecklenburg-Vorpommern die Auskunft der Verbünde
    /// (über TripKit) genutzt wird.
    static let useRegionalKey = "dataSources.useRegional"

    static var useRegional: Bool {
        AppGroup.defaults.object(forKey: useRegionalKey) as? Bool ?? true
    }

    static func router(useVVO: Bool = DataSources.useVVO, useRegional: Bool = DataSources.useRegional) -> ProviderRouter {
        ProviderRouter(transitous: TransitousProvider(userAgent: TransitousProvider.userAgent(version: appVersion)),
                       vvo: useVVO ? VVOProvider() : nil, useRegional: useRegional)
    }

    static let tripKitURL = URL(string: "https://github.com/alexander-albers/tripkit")!

    /// Version aus der Info.plist (in App und Widget gleich).
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// Pflicht-Quellenangabe von Transitous.
    static let transitousSourcesURL = URL(string: "https://transitous.org/sources/")!
    static let openStreetMapURL = URL(string: "https://www.openstreetmap.org/copyright")!
}

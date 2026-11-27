// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import Foundation

/// Welche Datenquellen App, Widget und Live-Aktivität verwenden (Einstellung in der App Group).
enum DataSources {
    /// Ob die App die Auskunft der Verkehrsverbünde nutzt: im VVO-Gebiet die VVO-WebAPI (Preise, Auslastung),
    /// in Sachsen außerhalb des VVO, Bayern, Baden-Württemberg, NRW und Mecklenburg-Vorpommern die Verbünde über
    /// TripKit. Aus = alles über Transitous.
    static let useNetworksKey = "dataSources.useNetworks"
    /// Früherer Schalter nur für den VVO – sein Wert gilt, bis der neue einmal gesetzt wurde.
    static let legacyVVOKey = "dataSources.useVVO"

    static var useNetworks: Bool {
        let defaults = AppGroup.defaults
        return defaults.object(forKey: useNetworksKey) as? Bool ?? defaults.object(forKey: legacyVVOKey) as? Bool ?? true
    }

    /// Übernimmt einmalig den Wert des alten VVO-Schalters (wer den VVO ausgeschaltet hatte, behält das).
    static func migrate() {
        let defaults = AppGroup.defaults
        guard defaults.object(forKey: useNetworksKey) == nil else { return }
        defaults.set(useNetworks, forKey: useNetworksKey)
        defaults.removeObject(forKey: legacyVVOKey)
    }

    static func router(useNetworks: Bool = DataSources.useNetworks) -> ProviderRouter {
        ProviderRouter(transitous: TransitousProvider(userAgent: TransitousProvider.userAgent(version: appVersion)),
                       vvo: useNetworks ? VVOProvider(userAgent: TransitousProvider.userAgent(version: appVersion)) : nil, useRegional: useNetworks)
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

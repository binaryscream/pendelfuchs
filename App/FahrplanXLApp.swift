// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

@main
struct FahrplanXLApp: App {
    @State private var favorites = FavoritesStore()
    @State private var location = LocationProvider()
    @State private var savedTrips = SavedTripsStore()
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Abfahrten", systemImage: "clock") { HomeView() }
                Tab("Verbindungen", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { TripSearchView() }
                Tab("Meine Fahrten", systemImage: "star") { MyTripsView() }
            }
                .environment(favorites)
                .environment(savedTrips)
                .environment(location)
                .environment(\.transit, VVOProvider())
                .preferredColorScheme(appearance.colorScheme)
                // Live-Aktivitäten aktuell halten, solange die App offen ist (jede Minute).
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await TripActivityManager.shared.refreshAll()
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
        }
        // Im Hintergrund: iOS weckt die App gelegentlich kurz (nicht garantiert).
        .backgroundTask(.appRefresh(TripActivityManager.refreshTaskID)) {
            await TripActivityManager.shared.refreshAll()
        }
    }
}

extension EnvironmentValues {
    /// Aktive Datenquelle. Wird später durch den `ProviderRouter` ersetzt.
    @Entry var transit: any TransitProvider = VVOProvider()
}

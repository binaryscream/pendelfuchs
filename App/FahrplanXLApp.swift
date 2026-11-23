// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI
import WidgetKit

@main
struct FahrplanXLApp: App {
    @State private var favorites: FavoritesStore
    @State private var location = LocationProvider()
    @State private var savedTrips: SavedTripsStore
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system
    @AppStorage(DataSources.useVVOKey, store: AppGroup.defaults) private var useVVO = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.departures
    @State private var openStop: Stop?

    init() {
        // Daten liegen in der App Group, damit das Widget die Favoriten sieht.
        AppGroup.migrateFromStandardDefaults()
        _favorites = State(initialValue: FavoritesStore(defaults: AppGroup.defaults))
        _savedTrips = State(initialValue: SavedTripsStore(defaults: AppGroup.defaults))
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("Abfahrten", systemImage: "clock", value: AppTab.departures) { HomeView(openStop: $openStop) }
                Tab("Verbindungen", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    value: AppTab.trips) { TripSearchView() }
                Tab("Meine Fahrten", systemImage: "star", value: AppTab.saved) { MyTripsView() }
            }
                // Antippen des Widgets öffnet die Haltestelle.
                .onOpenURL { url in
                    guard let stop = DeepLink.stop(from: url) else { return }
                    selectedTab = .departures
                    openStop = stop
                }
                .environment(favorites)
                .environment(savedTrips)
                .environment(location)
                .environment(\.transit, DataSources.router(useVVO: useVVO))
                .preferredColorScheme(appearance.colorScheme)
                // Widgets zeigen standardmäßig den ersten Favoriten – nach Änderungen neu laden.
                .onChange(of: favorites.stops) { WidgetCenter.shared.reloadAllTimelines() }
                .onChange(of: useVVO) { WidgetCenter.shared.reloadAllTimelines() }
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

enum AppTab: Hashable {
    case departures, trips, saved
}

extension EnvironmentValues {
    /// Aktive Datenquelle (wählt je Anfrage zwischen Transitous und VVO).
    @Entry var transit: any TransitProvider = DataSources.router()
}

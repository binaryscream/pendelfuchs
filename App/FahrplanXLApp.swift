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
    @AppStorage(StopNameStyle.storageKey, store: AppGroup.defaults) private var stopNameStyle = StopNameStyle.withPlace
    @AppStorage(CancelledDisplay.hideKey, store: AppGroup.defaults) private var hideCancelled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.departures
    @State private var openStop: Stop?
    @State private var openRoute: RouteLink?

    init() {
        // Daten liegen in der App Group, damit das Widget die Favoriten sieht.
        AppGroup.migrateFromStandardDefaults()
        _favorites = State(initialValue: FavoritesStore(defaults: AppGroup.defaults))
        _savedTrips = State(initialValue: SavedTripsStore(defaults: AppGroup.defaults))
        // Knöpfe in der Live-Aktivität („Aktualisieren“, „Beenden“) laufen im App-Prozess.
        TripActivityActions.refresh = { await TripActivityManager.shared.refreshAll() }
        TripActivityActions.end = { await TripActivityManager.shared.end($0) }
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("Abfahrten", systemImage: "clock", value: AppTab.departures) { HomeView(openStop: $openStop) }
                Tab("Verbindungen", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    value: AppTab.trips) { TripSearchView(openRoute: $openRoute) }
                Tab("Meine Fahrten", systemImage: "star", value: AppTab.saved) { MyTripsView() }
                Tab("Einstellungen", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
            }
                // Antippen des Widgets öffnet die Haltestelle.
                .onOpenURL { url in
                    if let stop = DeepLink.stop(from: url) {
                        selectedTab = .departures
                        openStop = stop
                    } else if let route = DeepLink.route(from: url) {
                        // Strecken-Widget: Verbindungssuche mit dieser Strecke öffnen.
                        selectedTab = .trips
                        openRoute = RouteLink(query: TripQuery(origin: route.from, destination: route.to), trip: route.trip)
                    }
                }
                .environment(favorites)
                .environment(savedTrips)
                .environment(location)
                .environment(\.transit, DataSources.router(useVVO: useVVO))
                .preferredColorScheme(appearance.colorScheme)
                // Widgets zeigen standardmäßig den ersten Favoriten – nach Änderungen neu laden.
                .onChange(of: favorites.stops) { WidgetCenter.shared.reloadAllTimelines() }
                .onChange(of: useVVO) { WidgetCenter.shared.reloadAllTimelines() }
                .environment(\.stopNameStyle, stopNameStyle)
                .onChange(of: stopNameStyle) { WidgetCenter.shared.reloadAllTimelines() }
                .onChange(of: hideCancelled) { WidgetCenter.shared.reloadAllTimelines() }
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

/// Vom Strecken-Widget geöffnete Suche, optional mit der angetippten Verbindung.
struct RouteLink: Equatable {
    var query: TripQuery
    var trip: TripTarget?
}

enum AppTab: Hashable {
    case departures, trips, saved, settings
}

extension EnvironmentValues {
    /// Aktive Datenquelle (wählt je Anfrage zwischen Transitous und VVO).
    @Entry var transit: any TransitProvider = DataSources.router()
}

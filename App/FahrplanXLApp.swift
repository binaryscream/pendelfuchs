// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI
import UserNotifications
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
    @AppStorage(DelayDisplay.storageKey, store: AppGroup.defaults) private var delayDisplay = DelayDisplay.badge
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.departures
    @State private var openStop: Stop?
    @State private var openRoute: RouteLink?
    @State private var openSavedTrip: UUID?
    @State private var notificationRouter = NotificationRouter.shared

    init() {
        // Daten liegen in der App Group, damit das Widget die Favoriten sieht.
        AppGroup.migrateFromStandardDefaults()
        _favorites = State(initialValue: FavoritesStore(defaults: AppGroup.defaults))
        _savedTrips = State(initialValue: SavedTripsStore(defaults: AppGroup.defaults))
        // Knöpfe in der Live-Aktivität („Aktualisieren“, „Beenden“) laufen im App-Prozess.
        TripActivityActions.refresh = { await TripActivityManager.shared.refreshAll() }
        TripActivityActions.end = { await TripActivityManager.shared.end($0) }
        TripActivityActions.start = { id in
            guard let saved = SavedTripsStore(defaults: AppGroup.defaults).trip(id: id) else { return }
            try? await TripActivityManager.shared.start(saved)
        }
        // Benachrichtigungen auch zeigen, während die App offen ist.
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("Abfahrten", systemImage: "clock", value: AppTab.departures) { HomeView(openStop: $openStop) }
                Tab("Verbindungen", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    value: AppTab.trips) { TripSearchView(openRoute: $openRoute) }
                Tab("Meine Fahrten", systemImage: "star", value: AppTab.saved) { MyTripsView(openSavedTrip: $openSavedTrip) }
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
                    } else if let id = DeepLink.savedTrip(from: url) {
                        // Widget „Meine nächste Fahrt“: die Fahrt unter „Meine Fahrten“ öffnen.
                        selectedTab = .saved
                        openSavedTrip = id
                    }
                }
                // Angetippte Benachrichtigung: die betroffene Fahrt unter „Meine Fahrten“ öffnen.
                .onChange(of: notificationRouter.savedTripToOpen, initial: true) { _, id in
                    guard let id else { return }
                    selectedTab = .saved
                    openSavedTrip = id
                    notificationRouter.savedTripToOpen = nil
                }
                .environment(favorites)
                .environment(savedTrips)
                .environment(location)
                .environment(\.transit, DataSources.router(useVVO: useVVO))
                .preferredColorScheme(appearance.colorScheme)
                // Widgets zeigen standardmäßig den ersten Favoriten – nach Änderungen neu laden.
                .onChange(of: favorites.stops) {
                    WidgetCenter.shared.reloadAllTimelines()
                    FahrplanShortcuts.updateAppShortcutParameters()
                }
                // Siri kennt die Favoriten und gemerkten Fahrten als Auswahl in Sätzen.
                .task { FahrplanShortcuts.updateAppShortcutParameters() }
                .onChange(of: savedTrips.trips) {
                    FahrplanShortcuts.updateAppShortcutParameters()
                    // Das Widget „Meine nächste Fahrt“ zeigt gemerkte Fahrten.
                    WidgetCenter.shared.reloadTimelines(ofKind: "de.fahrplanxl.nexttrip")
                    // Gleich nach dem Anlegen der ersten regelmäßigen Fahrt um Erlaubnis fragen – nicht erst
                    // beim nächsten Öffnen der App.
                    Task { await TripNotifier.shared.requestAuthorizationIfNeeded() }
                }
                .onChange(of: useVVO) { WidgetCenter.shared.reloadAllTimelines() }
                .environment(\.stopNameStyle, stopNameStyle)
                .onChange(of: stopNameStyle) { WidgetCenter.shared.reloadAllTimelines() }
                .onChange(of: hideCancelled) { WidgetCenter.shared.reloadAllTimelines() }
                .onChange(of: delayDisplay) { WidgetCenter.shared.reloadAllTimelines() }
                // Live-Aktivitäten und Benachrichtigungen aktuell halten, solange die App offen ist (jede Minute).
                .task(id: scenePhase) {
                    guard scenePhase == .active else {
                        // Beim Wechsel in den Hintergrund die nächste Hintergrundabfrage planen.
                        if scenePhase == .background { TripActivityManager.shared.scheduleBackgroundRefresh() }
                        return
                    }
                    await TripNotifier.shared.requestAuthorizationIfNeeded()
                    while !Task.isCancelled {
                        await TripActivityManager.shared.refreshAll()
                        await TripNotifier.shared.checkAll()
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
        }
        // Im Hintergrund: iOS weckt die App gelegentlich kurz (nicht garantiert).
        .backgroundTask(.appRefresh(TripActivityManager.refreshTaskID)) {
            await TripActivityManager.shared.backgroundRefresh()
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

// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Startseite: Favoriten, Haltestellen in der Nähe und Suche.
struct HomeView: View {
    /// Von außen (Widget-Deep-Link) zu öffnende Haltestelle.
    @Binding var openStop: Stop?

    @Environment(FavoritesStore.self) private var favorites
    @Environment(RecentsStore.self) private var recents
    @Environment(LocationProvider.self) private var location
    @Environment(\.transit) private var transit
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var query = ""
    @State private var searchResults: [Stop] = []
    @State private var searchError: String?
    @State private var nearby: [Stop] = []
    @State private var nearbyError: String?
    /// Erst nach der ersten Antwort darf „Keine Haltestellen gefunden“ erscheinen.
    @State private var nearbyLoaded = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if query.isEmpty {
                    favoritesSection
                    recentSection
                    nearbySection
                } else {
                    searchSection
                }
            }
            .navigationTitle("Fahrplan XL")
            .sensoryFeedback(.success, trigger: favorites.stops.count)
            .navigationDestination(for: Stop.self) { StopDeparturesView(stop: $0) }
            .navigationDestination(for: DepartureRoute.self) { DepartureJourneyView(departure: $0.departure, stop: $0.stop) }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Haltestelle suchen")
            .task(id: query) { await search() }
            // Auch bei der Rückkehr in die App: neuer Ort, oder die Standortfreigabe wurde gerade erteilt.
            .task(id: scenePhase) { if scenePhase == .active { await loadNearby() } }
            .refreshable { await loadNearby() }
            .toolbar {
                if !favorites.stops.isEmpty && query.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
        }
        .onChange(of: openStop, initial: true) {
            guard let stop = openStop else { return }
            path = NavigationPath([stop])
            openStop = nil
        }
    }

    // MARK: Abschnitte

    @ViewBuilder private var favoritesSection: some View {
        Section("Favoriten") {
            if favorites.stops.isEmpty {
                Text("Tippe in einer Haltestelle auf den Stern, um sie hier anzuheften.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(favorites.stops) { stop in
                    NavigationLink(value: stop) { StopRow(stop: stop) }
                }
                .onDelete { favorites.remove(atOffsets: $0) }
                .onMove { favorites.move(fromOffsets: $0, toOffset: $1) }
            }
        }
    }

    /// Zuletzt geöffnete Haltestellen, soweit sie nicht schon Favoriten sind.
    @ViewBuilder private var recentSection: some View {
        let stops = recents.stops.filter { !favorites.contains($0) }.prefix(5)
        if !stops.isEmpty {
            Section("Zuletzt verwendet") {
                ForEach(Array(stops)) { stop in
                    NavigationLink(value: stop) { StopRow(stop: stop) }
                        .swipeActions(edge: .leading) { favoriteAction(stop) }
                        .swipeActions(edge: .trailing) {
                            Button("Entfernen", systemImage: "xmark") { recents.remove(stop) }
                        }
                }
            }
        }
    }

    @ViewBuilder private var nearbySection: some View {
        Section("In der Nähe") {
            switch location.status {
            case .denied:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ohne Standortfreigabe können keine Haltestellen in der Nähe angezeigt werden.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            case .failed where nearby.isEmpty:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Standort konnte nicht ermittelt werden.").foregroundStyle(.secondary)
                    Button("Erneut versuchen") { Task { await loadNearby() } }
                }
            case .idle:
                locatingRow
            case .locating where nearby.isEmpty:
                locatingRow
            case .located where !nearbyLoaded:
                locatingRow
            default:
                if let nearbyError {
                    Text(nearbyError).foregroundStyle(.secondary)
                } else if nearby.isEmpty {
                    Text("Keine Haltestellen in der Nähe gefunden.").foregroundStyle(.secondary)
                } else {
                    ForEach(nearby) { stop in
                        NavigationLink(value: stop) { StopRow(stop: stop) }
                            .swipeActions(edge: .leading) { favoriteAction(stop) }
                    }
                }
            }
        }
    }

    /// Nach rechts wischen: Haltestelle zu den Favoriten hinzufügen bzw. daraus entfernen.
    private func favoriteAction(_ stop: Stop) -> some View {
        let isFavorite = favorites.contains(stop)
        return Button(isFavorite ? "Entfernen" : "Favorit", systemImage: isFavorite ? "star.slash" : "star.fill") {
            favorites.toggle(stop)
        }
        .tint(isFavorite ? .gray : .yellow)
    }

    private var locatingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Standort wird ermittelt …").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var searchSection: some View {
        if let searchError {
            Text(searchError).foregroundStyle(.secondary)
        } else {
            ForEach(searchResults) { stop in
                NavigationLink(value: stop) { StopRow(stop: stop) }
                    .swipeActions(edge: .leading) { favoriteAction(stop) }
            }
        }
    }

    // MARK: Laden

    private func search() async {
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            searchError = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))   // Entprellen beim Tippen
        guard !Task.isCancelled else { return }
        do {
            let anchors = [location.coordinate].compactMap { $0 } + favorites.stops.compactMap(\.coordinate)
            searchResults = StopSearchRegion.narrow(try await transit.searchStops(query: q), around: anchors)
            searchError = searchResults.isEmpty ? "Keine Haltestelle gefunden." : nil
        } catch {
            // Beim Weitertippen wird die laufende Suche abgebrochen – das ist kein Fehler.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            searchError = error.localizedDescription
        }
    }

    private func loadNearby() async {
        await location.refresh()
        guard let coordinate = location.coordinate else { return }
        do {
            nearby = try await transit.nearbyStops(around: coordinate)
            nearbyError = nil
            nearbyLoaded = true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            nearbyError = error.localizedDescription
            nearbyLoaded = true
        }
    }
}

struct StopRow: View {
    let stop: Stop
    @Environment(\.stopNameStyle) private var style

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.label(style)).font(.body)
                if let second = stop.secondaryLine(style) {
                    Text(second).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let distance = stop.distance {
                Text(Measurement(value: Double(distance), unit: UnitLength.meters),
                     format: .measurement(width: .abbreviated, usage: .road))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

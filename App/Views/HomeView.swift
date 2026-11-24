// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Startseite: Favoriten, Haltestellen in der Nähe und Suche.
struct HomeView: View {
    /// Von außen (Widget-Deep-Link) zu öffnende Haltestelle.
    @Binding var openStop: Stop?

    @Environment(FavoritesStore.self) private var favorites
    @Environment(LocationProvider.self) private var location
    @Environment(\.transit) private var transit
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var searchResults: [Stop] = []
    @State private var searchError: String?
    @State private var nearby: [Stop] = []
    @State private var nearbyError: String?
    @State private var showSettings = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if query.isEmpty {
                    favoritesSection
                    nearbySection
                } else {
                    searchSection
                }
            }
            .navigationTitle("Fahrplan XL")
            .navigationDestination(for: Stop.self) { StopDeparturesView(stop: $0) }
            .navigationDestination(for: DepartureRoute.self) { DepartureJourneyView(departure: $0.departure, stop: $0.stop) }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Haltestelle suchen")
            .task(id: query) { await search() }
            .task { await loadNearby() }
            .refreshable { await loadNearby() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Einstellungen", systemImage: "gearshape") { showSettings = true }
                }
                if !favorites.stops.isEmpty && query.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
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
            case .failed:
                Text("Standort konnte nicht ermittelt werden.").foregroundStyle(.secondary)
            case .idle:
                locatingRow
            case .locating where nearby.isEmpty:
                locatingRow
            default:
                if let nearbyError {
                    Text(nearbyError).foregroundStyle(.secondary)
                } else if nearby.isEmpty {
                    Text("Keine Haltestellen in der Nähe gefunden.").foregroundStyle(.secondary)
                } else {
                    ForEach(nearby) { stop in
                        NavigationLink(value: stop) { StopRow(stop: stop) }
                    }
                }
            }
        }
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
            searchResults = try await transit.searchStops(query: q)
            searchError = searchResults.isEmpty ? "Keine Haltestelle gefunden." : nil
        } catch is CancellationError {
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func loadNearby() async {
        await location.refresh()
        guard let coordinate = location.coordinate else { return }
        do {
            nearby = try await transit.nearbyStops(around: coordinate)
            nearbyError = nil
        } catch is CancellationError {
        } catch {
            nearbyError = error.localizedDescription
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

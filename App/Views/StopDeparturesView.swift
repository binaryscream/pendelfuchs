// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Abfahrtsmonitor einer Haltestelle, aktualisiert sich alle 30 Sekunden.
struct StopDeparturesView: View {
    let stop: Stop

    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.transit) private var transit
    @Environment(\.scenePhase) private var scenePhase

    @State private var departures: [Departure] = []
    @State private var errorMessage: String?
    @State private var lastUpdate: Date?
    @State private var isLoading = true

    private let refreshInterval: Duration = .seconds(30)

    var body: some View {
        List {
            if let errorMessage, departures.isEmpty {
                ContentUnavailableView("Keine Daten", systemImage: "wifi.exclamationmark",
                                       description: Text(errorMessage))
            } else if departures.isEmpty && !isLoading {
                ContentUnavailableView("Keine Abfahrten", systemImage: "moon.zzz",
                                       description: Text("Hier fährt demnächst nichts ab."))
            } else {
                Section {
                    ForEach(departures) { departure in
                        // Countdown jede Viertelminute neu berechnen, ohne neu zu laden.
                        TimelineView(.periodic(from: .now, by: 15)) { context in
                            DepartureRow(departure: departure, now: context.date)
                        }
                    }
                } footer: {
                    if let lastUpdate {
                        Text("Stand \(lastUpdate.formatted(date: .omitted, time: .shortened)) · Daten: \(departures.first?.source?.displayName ?? "–")")
                    }
                }
            }
        }
        .overlay { if isLoading && departures.isEmpty { ProgressView() } }
        .navigationTitle(stop.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                favorites.toggle(stop)
            } label: {
                Image(systemName: favorites.contains(stop) ? "star.fill" : "star")
            }
            .accessibilityLabel(favorites.contains(stop) ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
        }
        .refreshable { await load() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: refreshInterval)
            }
        }
    }

    private func load() async {
        do {
            let result = try await transit.departures(at: stop, limit: 30)
            departures = result
            errorMessage = nil
            lastUpdate = .now
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

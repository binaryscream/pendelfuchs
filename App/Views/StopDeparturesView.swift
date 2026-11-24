// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Abfahrtsmonitor einer Haltestelle, aktualisiert sich alle 30 Sekunden.
/// „Früher“ blättert in die Vergangenheit, „Später“ zeigt weitere Abfahrten.
struct StopDeparturesView: View {
    let stop: Stop

    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.transit) private var transit
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.stopNameStyle) private var style

    @State private var departures: [Departure] = []
    @State private var errorMessage: String?
    @State private var lastUpdate: Date?
    @State private var isLoading = true
    /// Beginn des angezeigten Zeitfensters; `nil` = ab jetzt.
    @State private var windowStart: Date?
    @State private var limit = Self.defaultLimit
    @State private var loadingMore: Direction?

    private enum Direction { case earlier, later }

    private static let defaultLimit = 30
    private static let maxLimit = 150
    private let refreshInterval: Duration = .seconds(30)

    var body: some View {
        List {
            if let errorMessage, departures.isEmpty {
                ContentUnavailableView("Keine Daten", systemImage: "wifi.exclamationmark",
                                       description: Text(errorMessage))
            } else if departures.isEmpty && !isLoading {
                ContentUnavailableView("Keine Abfahrten", systemImage: "moon.zzz",
                                       description: Text("Hier fährt in diesem Zeitraum nichts ab."))
                Section {
                    moreButton("Später", systemImage: "chevron.down", direction: .later)
                }
            } else if !departures.isEmpty {
                Section {
                    moreButton("Früher", systemImage: "chevron.up", direction: .earlier)

                    ForEach(departures) { departure in
                        // Antippen öffnet den Fahrtverlauf.
                        NavigationLink(value: DepartureRoute(departure: departure, stop: stop)) {
                            // Countdown jede Viertelminute neu berechnen, ohne neu zu laden.
                            TimelineView(.periodic(from: .now, by: 15)) { context in
                                DepartureRow(departure: departure, now: context.date)
                            }
                        }
                        .disabled(departure.tripID == nil)
                    }

                    moreButton("Später", systemImage: "chevron.down", direction: .later)
                } header: {
                    if let windowStart {
                        HStack {
                            Text("Ab \(windowStart.formatted(date: .omitted, time: .shortened))")
                            Spacer()
                            Button("Zurück zu jetzt") { resetWindow() }
                                .font(.footnote)
                                .textCase(nil)
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
        .navigationTitle(stop.label(style))
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

    private func moreButton(_ title: String, systemImage: String, direction: Direction) -> some View {
        Button {
            Task { await loadMore(direction) }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if loadingMore == direction { ProgressView() }
            }
        }
        .disabled(loadingMore != nil)
    }

    private func loadMore(_ direction: Direction) async {
        loadingMore = direction
        defer { loadingMore = nil }
        switch direction {
        case .earlier:
            // 30 Minuten weiter zurück; Limit anheben, damit das spätere Ende der Liste nicht abgeschnitten wird.
            windowStart = (windowStart ?? .now).addingTimeInterval(-30 * 60)
            limit = min(Self.maxLimit, limit + 12)
        case .later:
            limit = min(Self.maxLimit, limit + 20)
        }
        await load()
    }

    private func resetWindow() {
        windowStart = nil
        limit = Self.defaultLimit
        Task { await load() }
    }

    private func load() async {
        do {
            let result = try await transit.departures(at: stop, limit: limit, from: windowStart)
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

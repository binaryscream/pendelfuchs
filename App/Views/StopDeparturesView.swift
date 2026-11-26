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
    @AppStorage(CancelledDisplay.hideKey, store: AppGroup.defaults) private var hideCancelled = false

    @State private var departures: [Departure] = []
    @State private var errorMessage: String?
    @State private var lastUpdate: Date?
    @State private var isLoading = true
    /// Beginn des angezeigten Zeitfensters; `nil` = ab jetzt.
    @State private var windowStart: Date?
    @State private var limit = Self.defaultLimit
    @State private var loadingMore: Direction?
    /// Linienfilter: leer = alle Linien. Bei genau einer Linie zusätzlich eine Richtung wählbar.
    @State private var lineFilter: Set<String> = []
    @State private var directionFilter: String?

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
                // Auch bei nur noch einer Linie zeigen, solange ein Filter gesetzt ist – sonst lässt er sich
                // nicht mehr aufheben.
                if lines.count > 1 || !lineFilter.isEmpty || directionFilter != nil {
                    Section { filterBar }
                }
                Section {
                    moreButton("Früher", systemImage: "chevron.up", direction: .earlier)

                    if visibleDepartures.isEmpty {
                        Text("Keine Abfahrten dieser Linie im angezeigten Zeitraum.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visibleDepartures) { departure in
                        // Antippen öffnet den Fahrtverlauf.
                        NavigationLink(value: DepartureRoute(departure: departure, stop: stop)) {
                            // Countdown jede Viertelminute neu berechnen, ohne neu zu laden.
                            TimelineView(.periodic(from: .now, by: 15)) { context in
                                DepartureRow(departure: departure, now: context.date,
                                             stopNames: [stop.name, stop.label(.withPlace)])
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
                    if errorMessage != nil {
                        Label("Aktualisieren fehlgeschlagen – die Liste kann veraltet sein.",
                              systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                    }
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

    // MARK: Linienfilter

    /// Linien an dieser Haltestelle (nach Liniennummer sortiert) mit ihrem Verkehrsmittel.
    private var lines: [(name: String, mode: TransportMode)] {
        var seen: [String: TransportMode] = [:]
        for departure in departures where seen[departure.line] == nil { seen[departure.line] = departure.mode }
        return seen.map { ($0.key, $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var visibleDepartures: [Departure] {
        departures.filter { departure in
            (lineFilter.isEmpty || lineFilter.contains(departure.line))
                && (directionFilter == nil || departure.direction == directionFilter)
        }
    }

    /// Linien zum Antippen; bei genau einer gewählten Linie darunter deren Richtungen.
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(lines, id: \.name) { line in
                        let selected = lineFilter.contains(line.name)
                        Button {
                            withAnimation(.snappy) {
                                if selected { lineFilter.remove(line.name) } else { lineFilter.insert(line.name) }
                                directionFilter = nil
                            }
                        } label: {
                            LineBadge(line: line.name, mode: line.mode, compact: true)
                                .opacity(lineFilter.isEmpty || selected ? 1 : 0.35)
                                .overlay {
                                    if selected {
                                        RoundedRectangle(cornerRadius: 7).stroke(.primary, lineWidth: 2).padding(-3)
                                    }
                                }
                                .padding(3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Linie \(line.name)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                    if !lineFilter.isEmpty {
                        Button("Alle") {
                            withAnimation(.snappy) { lineFilter = []; directionFilter = nil }
                        }
                        .font(.subheadline)
                        .padding(.leading, 4)
                    }
                }
            }
            if lineFilter.count == 1, let line = lineFilter.first {
                let directions = Array(Set(departures.filter { $0.line == line }.map(\.direction))).sorted()
                if directions.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(directions, id: \.self) { direction in
                                let selected = directionFilter == direction
                                Button {
                                    withAnimation(.snappy) { directionFilter = selected ? nil : direction }
                                } label: {
                                    Label(direction, systemImage: "arrow.right")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                                    in: Capsule())
                                        .foregroundStyle(selected ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
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
        // An der Obergrenze lädt „Später“ nichts mehr – dann auch nicht anbieten.
        .disabled(loadingMore != nil || (direction == .later && limit >= Self.maxLimit))
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
            let result = CancellationMemory.process(
                try await transit.departures(at: stop, limit: limit, from: windowStart), at: stop)
            departures = result.filter { !hideCancelled || $0.state != .cancelled }
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

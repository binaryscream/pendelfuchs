// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Liste der gefundenen Verbindungen mit „Früher“/„Später“.
struct TripResultsView: View {
    let initialQuery: TripQuery
    /// Verbindung, die nach dem ersten Laden gleich geöffnet wird (Antippen im Strecken-Widget).
    var autoOpen: TripTarget?
    var onAutoOpen: ((Trip) -> Void)?

    @Environment(\.transit) private var transit
    @Environment(\.stopNameStyle) private var style

    @State private var trips: [Trip] = []
    @State private var isLoading = true
    @State private var loadingMore: Direction?
    @State private var errorMessage: String?

    private enum Direction { case earlier, later }

    var body: some View {
        List {
            if let errorMessage, trips.isEmpty {
                ContentUnavailableView("Keine Verbindungen", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else if trips.isEmpty && !isLoading {
                ContentUnavailableView("Keine Verbindungen", systemImage: "tram",
                                       description: Text("Für diese Suche wurde nichts gefunden."))
            } else if !trips.isEmpty {
                Section {
                    moreButton("Früher", systemImage: "chevron.up", direction: .earlier)
                    ForEach(trips) { trip in
                        NavigationLink(value: TripRoute.detail(trip, initialQuery)) {
                            // Pro Zeile, damit jede Verbindung eine eigene Listenzeile bleibt.
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                TripRow(trip: trip, now: context.date)
                            }
                        }
                    }
                    moreButton("Später", systemImage: "chevron.down", direction: .later)
                } header: {
                    header
                } footer: {
                    if errorMessage != nil {
                        Label("Laden fehlgeschlagen – die Liste kann veraltet sein.", systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .overlay { if isLoading && trips.isEmpty { ProgressView() } }
        .navigationTitle("\(initialQuery.origin.label(style)) → \(initialQuery.destination.label(style))")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(initialQuery, replace: true) }
        .task {
            // Nur beim ersten Erscheinen: Bei der Rückkehr aus einer Verbindung bleiben nachgeladene
            // („Früher“/„Später“) Verbindungen und die Position in der Liste erhalten.
            guard trips.isEmpty else { return }
            await load(initialQuery, replace: true)
            if let autoOpen, let trip = trips.first(where: autoOpen.matches) { onAutoOpen?(trip) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Start und Ziel stehen schon im Titel.
            if let via = initialQuery.via {
                Text("über \(via.label(style))")
            }
            if !initialQuery.options.isStandard {
                Label(initialQuery.options.summary, systemImage: "slider.horizontal.3")
            }
            Text("\(initialQuery.isArrivalTime ? "Ankunft" : "Abfahrt") \(initialQuery.time.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))")
        }
        .textCase(nil)
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
        guard let first = trips.first, let last = trips.last else { return }
        loadingMore = direction
        defer { loadingMore = nil }
        var query = initialQuery
        switch direction {
        case .earlier:
            // Verbindungen, die vor der bisher frühesten ankommen
            query.time = first.arrival.scheduledTime.addingTimeInterval(-60)
            query.isArrivalTime = true
        case .later:
            query.time = last.departure.scheduledTime.addingTimeInterval(60)
            query.isArrivalTime = false
        }
        await load(query, replace: false)
    }

    private func load(_ query: TripQuery, replace: Bool) async {
        do {
            let found = try await transit.trips(query)
            var merged = replace ? [:] : Dictionary(trips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for trip in found { merged[trip.id] = trip }
            // Nach tatsächlicher Abfahrt sortieren – so, wie man sie am Bahnsteig erlebt.
            trips = merged.values
                .filter { !CancelledDisplay.hide || !$0.isCancelledForRider }
                .sorted { $0.departure.expectedTime < $1.departure.expectedTime }
            errorMessage = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// Eine Verbindung in der Übersicht.
struct TripRow: View {
    let trip: Trip
    let now: Date
    @AppStorage(AlertDisplay.storageKey, store: AppGroup.defaults) private var alertDisplay = AlertDisplay.affected

    /// Abgefahren (ausgegraut) – ausgefallene bleiben deutlich sichtbar.
    private var departed: Bool { !trip.isCancelledForRider && trip.departure.expectedTime < now.addingTimeInterval(-60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                TimePointText(point: trip.departure, cancelled: trip.isCancelledForRider)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                TimePointText(point: trip.arrival, cancelled: trip.isCancelledForRider)
                Spacer()
                Text(durationText(trip.duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.title3.weight(.semibold))

            legChain

            HStack(spacing: 6) {
                // Nicht heute (z. B. nach „Später“ über Mitternacht): den Tag dazusagen.
                if !Calendar.current.isDate(trip.departure.scheduledTime, inSameDayAs: now) {
                    Text(relativeDay(trip.departure.scheduledTime, now: now).capitalizedFirst).fontWeight(.semibold)
                    Text("·")
                }
                if let disruption = trip.disruption {
                    Text(disruption.shortText).foregroundStyle(.red).fontWeight(.semibold)
                } else {
                    Text(trip.interchanges == 0 ? "Direkt" : trip.interchanges == 1 ? "1 Umstieg" : "\(trip.interchanges) Umstiege")
                    if let first = trip.rides.first?.stops.first, let platform = first.platform, !platform.isEmpty {
                        Text("·")
                        PlatformText(platform: platform, scheduled: first.scheduledPlatform,
                                     mode: trip.rides.first?.mode ?? .train)
                    }
                    if !alertDisplay.filter(trip).isEmpty {
                        Text("·")
                        Label("Hinweis", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if let price = trip.price { Text(price) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(departed ? 0.45 : 1)
    }

    private var legChain: some View {
        HStack(spacing: 4) {
            ForEach(Array(trip.legs.enumerated()), id: \.offset) { index, leg in
                if index > 0 {
                    Image(systemName: "chevron.compact.right").font(.caption2).foregroundStyle(.tertiary)
                }
                switch leg.kind {
                case .ride:
                    LineBadge(line: leg.line ?? "?", mode: leg.mode ?? .other, compact: true)
                case .walk:
                    HStack(spacing: 1) {
                        Image(systemName: "figure.walk")
                        if let minutes = leg.durationMinutes, minutes > 0 { Text("\(minutes)") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(leg.durationMinutes ?? 0) Minuten Fußweg")
                }
            }
        }
        .lineLimit(1)
    }
}

/// Zeit mit Verspätung in der Darstellung aus den Einstellungen („06:23 +3“, „06:26“ oder Plan/Ist untereinander).
struct TimePointText: View {
    let point: TimePoint
    var cancelled = false

    var body: some View {
        DelayedTimeText(scheduled: point.scheduledTime, actual: point.realTime, cancelled: cancelled)
    }
}

func durationText(_ interval: TimeInterval) -> String {
    let minutes = Int((interval / 60).rounded())
    return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
}

private extension String {
    /// „morgen“ → „Morgen“ (Wochentage sind schon großgeschrieben).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

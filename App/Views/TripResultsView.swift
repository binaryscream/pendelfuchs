// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Liste der gefundenen Verbindungen mit „Früher“/„Später“.
struct TripResultsView: View {
    let initialQuery: TripQuery

    @Environment(\.transit) private var transit

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
                }
            }
        }
        .overlay { if isLoading && trips.isEmpty { ProgressView() } }
        .navigationTitle("\(initialQuery.origin.name) → \(initialQuery.destination.name)")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(initialQuery, replace: true) }
        .task { await load(initialQuery, replace: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(initialQuery.origin.displayName) → \(initialQuery.destination.displayName)")
            if let via = initialQuery.via {
                Text("über \(via.displayName)")
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
            trips = merged.values.sorted { $0.departure.scheduledTime < $1.departure.scheduledTime }
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

    private var departed: Bool { trip.departure.expectedTime < now.addingTimeInterval(-60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                TimePointText(point: trip.departure)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                TimePointText(point: trip.arrival)
                Spacer()
                Text(durationText(trip.duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.title3.weight(.semibold))

            legChain

            HStack(spacing: 6) {
                if trip.isCancelled {
                    Text("Fahrt fällt (teilweise) aus").foregroundStyle(.red).fontWeight(.semibold)
                } else {
                    Text(trip.interchanges == 0 ? "Direkt" : trip.interchanges == 1 ? "1 Umstieg" : "\(trip.interchanges) Umstiege")
                    if let platform = trip.rides.first?.stops.first?.platform, !platform.isEmpty {
                        Text("·")
                        Text(trip.rides.first?.mode?.usesTracks == true ? "Gl. \(platform)" : "Steig \(platform)")
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

/// „06:23 +3“ – Planzeit mit farbiger Verspätung.
struct TimePointText: View {
    let point: TimePoint

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(point.scheduledTime, format: .dateTime.hour().minute())
                .monospacedDigit()
            if let delay = point.delayMinutes, delay != 0 {
                Text(delay > 0 ? "+\(delay)" : "\(delay)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(delay >= 3 ? .red : .orange)
            }
        }
    }
}

func durationText(_ interval: TimeInterval) -> String {
    let minutes = Int((interval / 60).rounded())
    return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
}

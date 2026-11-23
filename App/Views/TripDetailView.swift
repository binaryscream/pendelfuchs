// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Einzelne Verbindung mit allen Fahrten, Umstiegen und Zwischenhalten.
struct TripDetailView: View {
    let trip: Trip
    /// Die Suche, aus der die Verbindung stammt (Start/Ziel/Zwischenhalt zum Merken).
    let query: TripQuery

    @Environment(SavedTripsStore.self) private var savedTrips
    @State private var editing: SavedTrip?
    /// Für die Live-Aktivität einer nicht gemerkten Fahrt – einmal erzeugt, damit die ID stabil bleibt.
    @State private var adHoc: SavedTrip

    init(trip: Trip, query: TripQuery) {
        self.trip = trip
        self.query = query
        _adHoc = State(initialValue: SavedTrip(trip: trip, query: query))
    }

    var body: some View {
        let saved = savedTrips.saved(matching: trip, query: query)
        content
            .toolbar {
                Button {
                    // Neu merken – oder die bereits gemerkte Fahrt bearbeiten (Wochentage, Name, Löschen).
                    editing = saved ?? savedTrips.add(trip, query: query)
                } label: {
                    Image(systemName: saved == nil ? "star" : "star.fill")
                }
                .accessibilityLabel(saved == nil ? "Fahrt merken" : "Gemerkte Fahrt bearbeiten")
            }
            .sheet(item: $editing) { SavedTripSheet(id: $0.id) }
    }

    private var content: some View {
        List {
            Section {
                summary
            }

            // Nur für Fahrten, die noch nicht vorbei sind.
            if trip.arrival.expectedTime > .now {
                Section {
                    LiveActivityButton(saved: savedTrips.saved(matching: trip, query: query) ?? adHoc, knownTrip: trip)
                }
            }

            ForEach(Array(trip.legs.enumerated()), id: \.offset) { _, leg in
                switch leg.kind {
                case .ride:
                    RideSection(leg: leg)
                case .walk:
                    Section {
                        Label(walkText(leg), systemImage: "figure.walk")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(trip.departure.scheduledTime.formatted(.dateTime.weekday(.wide).day().month()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                TimePointText(point: trip.departure)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                TimePointText(point: trip.arrival)
                Spacer()
                Text(durationText(trip.duration)).foregroundStyle(.secondary)
            }
            .font(.title2.weight(.semibold))

            Text(trip.interchanges == 0 ? "Ohne Umstieg" : trip.interchanges == 1 ? "1 Umstieg" : "\(trip.interchanges) Umstiege")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let price = trip.price {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "ticket")
                    Text("Einzelfahrt \(price)")
                    if let zones = trip.fareZones {
                        Text("· \(zones)").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private func walkText(_ leg: TripLeg) -> String {
        guard let minutes = leg.durationMinutes, minutes > 0 else { return "Umsteigen" }
        return "\(minutes) min Fußweg"
    }
}

/// Eine Fahrt: Einstieg, aufklappbare Zwischenhalte, Ausstieg.
private struct RideSection: View {
    let leg: TripLeg
    @State private var showStops = false

    var body: some View {
        Section {
            HStack(spacing: 10) {
                LineBadge(line: leg.line ?? "?", mode: leg.mode ?? .other)
                VStack(alignment: .leading, spacing: 1) {
                    if let direction = leg.direction {
                        Text("Richtung \(direction)").font(.subheadline.weight(.medium))
                    }
                    if let op = leg.operatorName {
                        Text(op).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let first = leg.stops.first {
                StopLine(stop: first, time: first.departure, mode: leg.mode, emphasized: true)
            }

            if !leg.intermediateStops.isEmpty {
                DisclosureGroup(isExpanded: $showStops) {
                    ForEach(Array(leg.intermediateStops.enumerated()), id: \.offset) { _, stop in
                        StopLine(stop: stop, time: stop.departure ?? stop.arrival, mode: leg.mode, emphasized: false,
                                 // Ort nur nennen, wenn er vom Zielort abweicht („Bahnhof“ allein ist mehrdeutig).
                                 showPlace: stop.place != leg.stops.last?.place)
                    }
                } label: {
                    Text(stopsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let last = leg.stops.last {
                StopLine(stop: last, time: last.arrival, mode: leg.mode, emphasized: true)
            }
        } footer: {
            if !leg.notes.isEmpty {
                Text(leg.notes.joined(separator: " · "))
            }
        }
    }

    private var stopsSummary: String {
        let count = leg.intermediateStops.count
        var text = count == 1 ? "1 Zwischenhalt" : "\(count) Zwischenhalte"
        if let minutes = leg.durationMinutes { text += " · \(minutes) min" }
        return text
    }
}

private struct StopLine: View {
    let stop: TripStop
    let time: TimePoint?
    let mode: TransportMode?
    let emphasized: Bool
    var showPlace = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if let time { TimePointText(point: time) } else { Text("–") }
            }
            .frame(width: 70, alignment: .leading)
            .font(emphasized ? .body.weight(.semibold) : .subheadline)

            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name)
                    .font(emphasized ? .body.weight(.semibold) : .subheadline)
                    .strikethrough(stop.isCancelled)
                if emphasized || showPlace, let place = stop.place {
                    Text(place).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if emphasized, let platform = stop.platform, !platform.isEmpty {
                Text(mode?.usesTracks == true ? "Gl. \(platform)" : "Steig \(platform)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .foregroundStyle(stop.isCancelled ? .red : .primary)
    }
}

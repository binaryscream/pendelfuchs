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
    @State private var showMap = false

    init(trip: Trip, query: TripQuery) {
        self.trip = trip
        self.query = query
        _adHoc = State(initialValue: SavedTrip(trip: trip, query: query))
    }

    var body: some View {
        let saved = savedTrips.saved(matching: trip, query: query)
        content
            .toolbar {
                if trip.rides.contains(where: { !$0.drawablePath.isEmpty }) {
                    Button("Karte", systemImage: "map") { showMap = true }
                }
                Button {
                    // Neu merken – oder die bereits gemerkte Fahrt bearbeiten (Wochentage, Name, Löschen).
                    editing = saved ?? savedTrips.add(trip, query: query)
                } label: {
                    Image(systemName: saved == nil ? "star" : "star.fill")
                }
                .accessibilityLabel(saved == nil ? "Fahrt merken" : "Gemerkte Fahrt bearbeiten")
            }
            .sheet(item: $editing) { SavedTripSheet(id: $0.id) }
            .fullScreenCover(isPresented: $showMap) { TripMapView(trip: trip) }
    }

    private var content: some View {
        // Fortschritt alle 20 Sekunden neu berechnen.
        TimelineView(.periodic(from: .now, by: 20)) { context in
            list(now: context.date)
        }
        .navigationTitle(trip.departure.scheduledTime.formatted(.dateTime.weekday(.wide).day().month()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func list(now: Date) -> some View {
        List {
            Section {
                summary(now: now)
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
                    RideSection(leg: leg, now: now)
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
    }

    private func summary(now: Date) -> some View {
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

            TripStatusView(trip: trip, now: now)

            if let source = trip.source {
                Text("Daten: \(source.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

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
    let now: Date
    @State private var showStops = false

    var body: some View {
        let progress = leg.progress(at: now)
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

            if case .underway(let passed, let fraction) = progress, passed + 1 < leg.stops.count {
                NextStopRow(next: leg.stops[passed + 1], fraction: fraction, mode: leg.mode ?? .other, now: now)
            }

            if let first = leg.stops.first {
                StopLine(stop: first, time: first.departure, mode: leg.mode, emphasized: true,
                         passed: progress.hasPassed(0))
            }

            if !leg.intermediateStops.isEmpty {
                DisclosureGroup(isExpanded: $showStops) {
                    ForEach(Array(leg.intermediateStops.enumerated()), id: \.offset) { offset, stop in
                        StopLine(stop: stop, time: stop.departure ?? stop.arrival, mode: leg.mode, emphasized: false,
                                 // Ort nur nennen, wenn er vom Zielort abweicht („Bahnhof“ allein ist mehrdeutig).
                                 showPlace: stop.place != leg.stops.last?.place,
                                 passed: progress.hasPassed(offset + 1))
                    }
                } label: {
                    Text(stopsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let last = leg.stops.last {
                StopLine(stop: last, time: last.arrival, mode: leg.mode, emphasized: true,
                         passed: progress == .finished)
            }
        } footer: {
            if !leg.notes.isEmpty {
                Text(leg.notes.joined(separator: " · "))
            }
        }
        // Während der Fahrt die Zwischenhalte automatisch aufklappen.
        .onAppear {
            if case .underway = progress { showStops = true }
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
    var passed = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(passed ? AnyShapeStyle(.tertiary) : AnyShapeStyle((mode ?? .other).color))
                .accessibilityLabel(passed ? "passiert" : "")
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
        .foregroundStyle(stop.isCancelled ? AnyShapeStyle(.red) : passed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
}

/// „Nächster Halt: Hauptbahnhof · in 3 min“ mit Fortschrittsbalken bis dorthin.
private struct NextStopRow: View {
    let next: TripStop
    let fraction: Double
    let mode: TransportMode
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill").foregroundStyle(mode.color)
                Text("Nächster Halt: \(next.name)").font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let time = (next.arrival ?? next.departure)?.expectedTime {
                    Text(minutesUntil(time, now: now)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: fraction).tint(mode.color)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Gesamtfortschritt: vor der Abfahrt, unterwegs, angekommen.
private struct TripStatusView: View {
    let trip: Trip
    let now: Date

    var body: some View {
        let departure = trip.departure.expectedTime
        let arrival = trip.arrival.expectedTime
        if now >= arrival {
            Label("Angekommen", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
        } else if let progress = trip.overallProgress(at: now) {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(trip.rides.first?.mode?.color ?? .accentColor)
                Text("Unterwegs · noch \(remaining(until: arrival, now: now)) bis zur Ankunft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        } else if departure.timeIntervalSince(now) < 3 * 3600 {
            Label("Abfahrt \(minutesUntil(departure, now: now))", systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// „5 min“, „1 h 20 min“ (aufgerundet, mindestens 1 min).
private func remaining(until date: Date, now: Date) -> String {
    let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
}

/// „in 5 min“ bzw. „jetzt“.
private func minutesUntil(_ date: Date, now: Date) -> String {
    date <= now ? "jetzt" : "in \(remaining(until: date, now: now))"
}

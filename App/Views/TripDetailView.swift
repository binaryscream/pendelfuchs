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
    @State private var sheetIsNew = true

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
                if let saved {
                    // Schon gemerkt: Einstellungen (Wochentage, Name) liegen hinter einem Menü.
                    Menu {
                        Button("Einstellungen", systemImage: "slider.horizontal.3") {
                            sheetIsNew = false
                            editing = saved
                        }
                        Button("Nicht mehr merken", systemImage: "star.slash", role: .destructive) {
                            savedTrips.remove(id: saved.id)
                        }
                    } label: {
                        Image(systemName: "star.fill")
                    }
                    .accessibilityLabel("Gemerkte Fahrt")
                } else {
                    // Erstes Antippen: merken und direkt die Wochentage anbieten.
                    Button {
                        sheetIsNew = true
                        editing = savedTrips.add(trip, query: query)
                    } label: {
                        Image(systemName: "star")
                    }
                    .accessibilityLabel("Fahrt merken")
                }
            }
            .sheet(item: $editing) { SavedTripSheet(id: $0.id, isNew: sheetIsNew) }
            .fullScreenCover(isPresented: $showMap) { TripMapView(trip: trip) }
    }

    private var content: some View {
        // Fortschritt jede Sekunde neu berechnen; die Anzeige gleitet dazwischen (siehe `.animation` an Leiste/Balken).
        TimelineView(.periodic(from: .now, by: 1)) { context in
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
            if trip.arrival.expectedTime > .now, trip.disruption == nil {
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
        .listRowSpacing(0) // Zeitleiste ohne Lücken zwischen den Zeilen
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

/// Eine Fahrt: Linie, „Nächster Halt“ und die Zeitleiste mit allen Halten.
private struct RideSection: View {
    let leg: TripLeg
    let now: Date
    @State private var showCoachSequence = false
    /// Fahrt mit DB-Auslastung (Züge), sobald geladen.
    @State private var dbLeg: TripLeg?

    var body: some View {
        let progress = leg.progress(at: now)
        Section {
            RideHeader(leg: dbLeg ?? leg)
                .task(id: leg.departure?.scheduledTime) {
                    guard leg.boardingOccupancy == nil, DBOccupancyProvider.supports(leg) else { return }
                    let enriched = await DBOccupancyProvider().enrich(leg)
                    if enriched.boardingOccupancy != nil { dbLeg = enriched }
                }

            if DBCoachSequenceProvider.supports(leg) {
                Button { showCoachSequence = true } label: {
                    Label("Wagenreihung", systemImage: "train.side.front.car")
                }
                .sheet(isPresented: $showCoachSequence) { CoachSequenceView(leg: leg) }
            }

            if case .underway(let passed, let fraction) = progress, passed + 1 < leg.stops.count {
                NextStopRow(next: leg.stops[passed + 1], fraction: fraction, mode: leg.mode ?? .other, now: now)
            }

            RideTimeline(leg: leg, now: now)
        } footer: {
            if !leg.notes.isEmpty {
                Text(leg.notes.joined(separator: " · "))
            }
        }
    }
}

/// Liniennummer, Richtung und Betreiber.
struct RideHeader: View {
    let leg: TripLeg
    /// Halt, für den die Auslastung gezeigt wird (Abfahrtsmonitor: „Hier“); sonst der Einstieg.
    var stopIndex: Int?

    private var occupancy: Occupancy? {
        if let stopIndex, leg.stops.indices.contains(stopIndex), let value = leg.stops[stopIndex].occupancy { return value }
        return leg.boardingOccupancy
    }

    var body: some View {
        HStack(spacing: 10) {
            LineBadge(line: leg.line ?? "?", mode: leg.mode ?? .other)
            VStack(alignment: .leading, spacing: 1) {
                if let direction = leg.direction {
                    Text("Richtung \(direction)").font(.subheadline.weight(.medium))
                }
                let details = [leg.trainNumber.map { "Zug \($0)" }, leg.operatorName].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                if let occupancy {
                    OccupancyView(occupancy: occupancy, showsTitle: true).font(.caption)
                }
            }
        }
    }
}

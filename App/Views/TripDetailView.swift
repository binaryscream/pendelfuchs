// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Einzelne Verbindung mit allen Fahrten, Umstiegen und Zwischenhalten.
struct TripDetailView: View {
    /// Startet mit dem Stand aus der Suche und wird danach laufend mit Echtzeitdaten aufgefrischt.
    @State private var trip: Trip
    @State private var lastUpdate: Date?
    /// Die Suche, aus der die Verbindung stammt (Start/Ziel/Zwischenhalt zum Merken).
    let query: TripQuery

    @Environment(SavedTripsStore.self) private var savedTrips
    @Environment(\.transit) private var transit
    @State private var editing: SavedTrip?
    /// Ganzer Lauf je Fahrt (Index in `trip.legs`) – damit die Live-Position auch vor dem Einstieg passt.
    @State private var runs: [Int: TripLeg] = [:]
    /// Für die Live-Aktivität einer nicht gemerkten Fahrt – einmal erzeugt, damit die ID stabil bleibt.
    @State private var adHoc: SavedTrip
    @State private var showMap = false
    @State private var sheetIsNew = true

    init(trip: Trip, query: TripQuery) {
        _trip = State(initialValue: trip)
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
                            Task { await TripActivityManager.shared.end(saved.id) }
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
            .fullScreenCover(isPresented: $showMap) { TripMapView(trip: trip, runs: runs) }
            // Live-Positionen (TLMS) nur für Straßenbahnen/Stadtbusse in Dresden und nur bis zur Ankunft.
            .task {
                guard trip.mayHaveLiveVehicles, trip.arrival.expectedTime > .now else { return }
                await LiveVehicleFeed.shared.keepUpdated()
            }
            .task { await loadRuns() }
            .task { await keepFresh() }
    }

    /// Holt die Verbindung regelmäßig neu, damit Verspätungen, Gleiswechsel und Ausfälle auch dann erscheinen,
    /// wenn die Ansicht offen bleibt. Wird sie nicht wiedergefunden, bleibt der letzte Stand stehen.
    private func keepFresh() async {
        while !Task.isCancelled, trip.arrival.expectedTime.addingTimeInterval(10 * 60) > .now {
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            var fresh = query
            // Etwas früher suchen: Eine Minute Fahrplanabweichung soll die Verbindung nicht aus dem Ergebnis werfen.
            fresh.time = trip.departure.scheduledTime.addingTimeInterval(-3 * 60)
            fresh.isArrivalTime = false
            if let found = try? await transit.trips(fresh), let match = found.first(where: { $0.id == trip.id }) {
                trip = match
                lastUpdate = .now
            }
        }
    }

    /// Lädt den ganzen Lauf jeder Fahrt, die live verfolgt werden kann (jede Minute neu, wegen der Echtzeit).
    private func loadRuns() async {
        while !Task.isCancelled, trip.arrival.expectedTime > .now {
            for (index, leg) in trip.legs.enumerated() where leg.tlmsLine != nil {
                // Erst kurz vor der Abfahrt interessant (anrollende Bahn).
                guard let start = leg.departure?.expectedTime, start.timeIntervalSinceNow < 30 * 60,
                      let end = leg.arrival?.expectedTime, end > .now else { continue }
                if let run = await transit.fullRun(of: leg, source: trip.source) { runs[index] = run }
            }
            try? await Task.sleep(for: .seconds(60))
        }
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
                    LiveActivityButton(saved: savedTrips.saved(matching: trip, query: query) ?? adHoc, knownTrip: trip,
                                       otherID: adHoc.id)
                }
            }

            ForEach(Array(trip.legs.enumerated()), id: \.offset) { index, leg in
                switch leg.kind {
                case .ride:
                    RideSection(leg: leg, now: now,
                                live: LiveVehicleFeed.shared.state(for: leg, run: runs[index], at: now))
                case .walk:
                    Section {
                        Label(walkText(leg), systemImage: "figure.walk")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Ganz unten: Kalender und Buchung.
            if trip.arrival.expectedTime > .now {
                TripActionsSection(trip: trip)
            }
        }
        .listSectionSpacing(.compact)
        .listRowSpacing(0) // Zeitleiste ohne Lücken zwischen den Zeilen
    }

    private func summary(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                TimePointText(point: trip.departure, cancelled: trip.isCancelledForRider)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                TimePointText(point: trip.arrival, cancelled: trip.isCancelledForRider)
                Spacer()
                Text(durationText(trip.duration)).foregroundStyle(.secondary)
            }
            .font(.title2.weight(.semibold))

            Text(trip.interchanges == 0 ? "Ohne Umstieg" : trip.interchanges == 1 ? "1 Umstieg" : "\(trip.interchanges) Umstiege")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TripStatusView(trip: trip, now: now)

            if let source = trip.source {
                Text("Daten: \(source.displayName)"
                     + (lastUpdate.map { " · Stand \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
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
struct RideSection: View {
    let leg: TripLeg
    let now: Date
    /// Live-Zustand laut TLMS, falls ein passendes Fahrzeug gemeldet ist.
    var live: LiveRideState?
    @AppStorage(AlertDisplay.storageKey, store: AppGroup.defaults) private var alertDisplay = AlertDisplay.affected

    var body: some View {
        let progress = live?.progress ?? leg.progress(at: now)
        Section {
            RideHeader(leg: leg)

            ForEach(alertDisplay.filter(leg)) { AlertRow(alert: $0) }

            if let live, live.stopsAway != nil {
                ApproachingRow(state: live, mode: leg.mode ?? .other, now: now)
            }
            if case .underway(let passed, let fraction) = progress, passed + 1 < leg.stops.count {
                NextStopRow(next: leg.stops[passed + 1], fraction: fraction, mode: leg.mode ?? .other, now: now,
                            isLive: live != nil)
            }

            RideTimeline(leg: leg, now: now, liveProgress: live?.progress)
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
                let isTrain = [.suburbanRailway, .train, .longDistance].contains(leg.mode ?? .other)
                let details = [isTrain ? leg.trainNumber.map { "Zug \($0)" } : nil, leg.operatorName].compactMap { $0 }
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

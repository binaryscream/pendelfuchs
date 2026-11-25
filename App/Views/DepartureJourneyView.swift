// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Navigationsziel: eine Abfahrt an einer Haltestelle.
struct DepartureRoute: Hashable {
    let departure: Departure
    let stop: Stop
}

/// Fahrtverlauf einer Abfahrt aus dem Abfahrtsmonitor: alle Halte als Zeitleiste, Fortschritt, Karte.
struct DepartureJourneyView: View {
    let departure: Departure
    let stop: Stop

    @Environment(\.transit) private var transit
    @Environment(\.scenePhase) private var scenePhase

    @State private var leg: TripLeg?
    @State private var errorMessage: String?
    @State private var showMap = false

    var body: some View {
        Group {
            if let leg {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(leg: leg, now: context.date)
                }
            } else if let errorMessage {
                ContentUnavailableView("Kein Fahrtverlauf", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                       description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("\(departure.line) → \(departure.direction)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let leg, !leg.drawablePath.isEmpty {
                Button("Karte", systemImage: "map") { showMap = true }
            }
        }
        .fullScreenCover(isPresented: $showMap) {
            if let leg { TripMapView(trip: Trip(legs: [leg], interchanges: 0, source: departure.source)) }
        }
        // Live-Positionen (TLMS), sobald klar ist, dass die Fahrt dafür infrage kommt.
        .task(id: leg?.tlmsLine) {
            guard leg?.tlmsLine != nil else { return }
            await LiveVehicleFeed.shared.keepUpdated()
        }
        // Echtzeit alle 30 Sekunden neu laden, solange die App sichtbar ist.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func content(leg: TripLeg, now: Date) -> some View {
        let live = LiveVehicleFeed.shared.state(for: leg, at: now)
        let progress = live?.progress ?? leg.progress(at: now)
        return List {
            Section {
                RideHeader(leg: leg, stopIndex: highlightedIndex(in: leg))
                ForEach(journeyAlerts(leg)) { AlertRow(alert: $0) }
                TripStatusView(trip: Trip(legs: [leg], interchanges: 0), now: now)
            } footer: {
                if let source = departure.source {
                    Text("Daten: \(source.displayName)")
                }
            }

            Section {
                if case .underway(let passed, let fraction) = progress, passed + 1 < leg.stops.count {
                    NextStopRow(next: leg.stops[passed + 1], fraction: fraction, mode: leg.mode ?? .other, now: now,
                                isLive: live != nil)
                }
                RideTimeline(leg: leg, now: now, highlightedStopIndex: highlightedIndex(in: leg),
                             liveProgress: live?.progress)
            }
        }
        .listSectionSpacing(.compact)
        .listRowSpacing(0) // Zeitleiste ohne Lücken zwischen den Zeilen
    }

    /// Hinweise für den Weg ab der eigenen Haltestelle.
    private func journeyAlerts(_ leg: TripLeg) -> [ServiceAlert] {
        var ahead = leg
        if let index = highlightedIndex(in: leg) { ahead.stops = Array(leg.stops[index...]) }
        return AlertDisplay.current.filter(departure.alerts, names: ahead.stopNames)
    }

    /// Die Haltestelle, an der man im Abfahrtsmonitor war („Hier“).
    private func highlightedIndex(in leg: TripLeg) -> Int? {
        let byID = leg.stops.firstIndex { $0.stopID == stop.stopID || $0.stopID.hasPrefix(stop.stopID + ":") }
        if let byID { return byID }
        // Unterschiedliche ID-Formate (Bahnsteig vs. Haltestelle): über den Namen und die Abfahrtszeit.
        return leg.stops.firstIndex {
            ($0.name == stop.name || $0.name.hasSuffix(stop.name))
                && abs(($0.departure?.scheduledTime ?? .distantPast).timeIntervalSince(departure.scheduledTime)) < 120
        }
    }

    private func load() async {
        do {
            var loaded = try await transit.journey(of: departure, at: stop)
            // Linie/Richtung aus der Abfahrt übernehmen, falls die Quelle sie im Verlauf nicht mitliefert.
            if loaded.line == nil { loaded.line = departure.line }
            if loaded.direction == nil { loaded.direction = departure.direction }
            if loaded.mode == nil { loaded.mode = departure.mode }
            leg = loaded
            errorMessage = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            if leg == nil { errorMessage = error.localizedDescription }
        }
    }
}

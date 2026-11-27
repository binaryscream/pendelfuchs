// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import Foundation
import Observation

/// Gemeinsame Live-Fahrzeugdaten (TLMS, Dresden) für alle Ansichten.
///
/// Mehrere offene Ansichten (Fahrtdetails, Karte) teilen sich eine Abfrage: Geladen wird höchstens alle
/// 12 Sekunden, und nur solange eine Ansicht `keepUpdated()` laufen lässt.
@MainActor @Observable
final class LiveVehicleFeed {
    static let shared = LiveVehicleFeed()

    private(set) var vehicles: [LiveVehicle] = []

    /// Mit dem User-Agent der App, damit TLMS die Anfragen zuordnen kann (Bitte von TLMS).
    @ObservationIgnored private let client = TLMSClient(
        userAgent: TransitousProvider.userAgent(version: DataSources.appVersion))
    @ObservationIgnored private var lastFetch = Date.distantPast
    @ObservationIgnored private var isFetching = false
    /// Einmal gefundenes Fahrzeug (Umlauf) je Fahrt, damit die Anzeige nicht zwischen Fahrzeugen springt.
    @ObservationIgnored private var lockedRuns: [String: Int] = [:]

    /// Hält die Daten aktuell, solange die aufrufende Aufgabe läuft (für `.task` einer Ansicht).
    func keepUpdated() async {
        while !Task.isCancelled {
            await refreshIfStale()
            try? await Task.sleep(for: .seconds(15))
        }
    }

    private func refreshIfStale() async {
        guard !isFetching, Date.now.timeIntervalSince(lastFetch) >= 12 else { return }
        isFetching = true
        defer { isFetching = false }
        lastFetch = .now
        if let fresh = try? await client.vehicles() { vehicles = fresh }
    }

    /// Live-Zustand einer Fahrt, falls TLMS ein passendes Fahrzeug meldet.
    /// - Parameter run: ganzer Lauf des Fahrzeugs (dann wird auch die anrollende Bahn erkannt).
    func state(for ride: TripLeg, run: TripLeg? = nil, at now: Date) -> LiveRideState? {
        guard ride.tlmsLine != nil, !vehicles.isEmpty else { return nil }
        let key = ride.liveKey
        guard let state = ride.liveState(in: vehicles, at: now, run: run, preferredRun: lockedRuns[key]) else {
            return nil
        }
        lockedRuns[key] = state.vehicle.run
        return state
    }
}

extension Trip {
    /// Kann für eine Fahrt dieser Verbindung eine Live-Position kommen (Straßenbahn/Stadtbus in Dresden)?
    var mayHaveLiveVehicles: Bool { rides.contains { $0.tlmsLine != nil } }
}

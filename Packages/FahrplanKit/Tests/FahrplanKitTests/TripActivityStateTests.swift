// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

@Suite struct TripActivityStateTests {
    let t0 = Date(timeIntervalSince1970: 1_795_497_780)   // 24.11.2026 06:23

    private func stop(_ name: String, platform: String, arr: Date?, dep: Date?, delay: TimeInterval = 0) -> TripStop {
        TripStop(stopID: name, name: name, place: nil, platform: platform,
                 arrival: arr.map { TimePoint(scheduledTime: $0, realTime: $0 + delay) },
                 departure: dep.map { TimePoint(scheduledTime: $0, realTime: $0 + delay) })
    }

    /// S1 06:23–06:45 (2 min verspätet), Umstieg, 7 06:50–06:56.
    private var trip: Trip {
        let m = { (minutes: Double) in self.t0 + minutes * 60 }
        let s1 = TripLeg(kind: .ride, mode: .suburbanRailway, line: "S1", direction: "Meißen", stops: [
            stop("Pirna", platform: "1", arr: nil, dep: m(0), delay: 120),
            stop("Hbf", platform: "14", arr: m(22), dep: nil, delay: 120),
        ])
        let tram = TripLeg(kind: .ride, mode: .tram, line: "7", direction: "Weixdorf", stops: [
            stop("Hbf", platform: "1", arr: nil, dep: m(27)),
            stop("Postplatz", platform: "4", arr: m(33), dep: nil),
        ])
        return Trip(legs: [s1, TripLeg(kind: .walk, durationMinutes: 3), tram], interchanges: 1)
    }

    @Test func buildsRidesWithoutWalks() {
        let state = TripActivityState(trip: trip, updatedAt: t0)
        #expect(state.rides.map(\.line) == ["S1", "7"])
        #expect(state.rides[0].fromPlatform == "1")
        #expect(state.rides[0].toName == "Hbf")
        #expect(state.departure.delayMinutes == 2)
        #expect(state.arrival.scheduledTime == t0 + 33 * 60)
    }

    @Test func phasesFollowTheClock() {
        let state = TripActivityState(trip: trip, updatedAt: t0)
        #expect(state.phase(at: t0 - 300) == .waiting)
        #expect(state.phase(at: t0 + 60) == .waiting, "S1 ist 2 min verspätet, also noch nicht abgefahren")
        #expect(state.phase(at: t0 + 10 * 60) == .riding(index: 0))
        #expect(state.phase(at: t0 + 25 * 60) == .transfer(index: 1))
        #expect(state.phase(at: t0 + 30 * 60) == .riding(index: 1))
        #expect(state.phase(at: t0 + 40 * 60) == .arrived)
    }

    @Test func countdownTargets() {
        let state = TripActivityState(trip: trip, updatedAt: t0)
        #expect(state.countdownTarget(at: t0 - 300) == t0 + 120)              // Abfahrt inkl. Verspätung
        #expect(state.countdownTarget(at: t0 + 10 * 60) == t0 + 24 * 60)      // Ankunft Hbf (+2)
        #expect(state.countdownTarget(at: t0 + 25 * 60) == t0 + 27 * 60)      // Abfahrt Straßenbahn
        #expect(state.focusRide(at: t0 + 25 * 60)?.line == "7")
        #expect(state.countdownTarget(at: t0 + 40 * 60) == nil)
    }

    @Test func fitsActivityKitSizeLimit() throws {
        let data = try JSONEncoder().encode(TripActivityState(trip: trip, updatedAt: t0))
        #expect(data.count < 4096)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

@Suite struct TripWatchTests {
    let t0 = Date(timeIntervalSince1970: 1_795_621_000)

    /// Bus 86 (0–15 min) und S2 ab 30 min bis 50 min (15 min Umstieg); Verspätungen in Minuten.
    private func trip(busDelay: Double = 0, trainDelay: Double = 0, trainPlatform: String? = nil,
                      trainCancelled: Bool = false) -> Trip {
        func point(_ minutes: Double, _ delay: Double) -> TimePoint {
            TimePoint(scheduledTime: t0 + minutes * 60, realTime: t0 + (minutes + delay) * 60)
        }
        let bus = TripLeg(kind: .ride, mode: .cityBus, line: "86", stops: [
            TripStop(stopID: "a", name: "Start", place: nil, platform: "1", arrival: nil, departure: point(0, busDelay)),
            TripStop(stopID: "b", name: "Bahnhof", place: nil, platform: nil, arrival: point(15, busDelay), departure: nil),
        ])
        var board = TripStop(stopID: "c", name: "Bahnhof", place: nil, platform: trainPlatform ?? "2", arrival: nil,
                             departure: point(30, trainDelay), isCancelled: trainCancelled)
        board.scheduledPlatform = "2"
        let train = TripLeg(kind: .ride, mode: .suburbanRailway, line: "S2", stops: [
            board,
            TripStop(stopID: "d", name: "Ziel", place: nil, platform: nil, arrival: point(50, trainDelay), departure: nil,
                     isCancelled: trainCancelled),
        ])
        return Trip(legs: [bus, train], interchanges: 1)
    }

    private func check(_ trip: Trip, at now: Date? = nil, memory: TripWatchMemory = .init(),
                       settings: TripWatchSettings = .init()) -> (notices: [TripNotice], memory: TripWatchMemory) {
        TripWatch.notices(for: trip, title: "Zur Arbeit", now: now ?? t0 - 600, memory: memory, settings: settings)
    }

    @Test func punctualTripStaysQuiet() {
        #expect(check(trip()).notices.isEmpty)
    }

    @Test func delayIsReportedOnceAndAgainWhenItGrows() {
        let first = check(trip(busDelay: 6))
        #expect(first.notices.map(\.kind) == [.delay])
        #expect(first.notices[0].body.contains("+6 min"))
        #expect(first.notices[0].title == "Zur Arbeit")

        #expect(check(trip(busDelay: 7), memory: first.memory).notices.isEmpty, "nur 1 min mehr")
        let worse = check(trip(busDelay: 11), memory: first.memory)
        #expect(worse.notices.map(\.kind) == [.delay])

        let better = check(trip(busDelay: 1), memory: worse.memory)
        #expect(better.notices.first?.body.contains("pünktlich") == true)
        #expect(better.memory.notifiedDelay == nil)
    }

    @Test func delayAroundThresholdDoesNotFlap() {
        let first = check(trip(busDelay: 5))
        #expect(first.notices.count == 1)
        // 4 min liegt knapp unter der Schwelle: weder Entwarnung noch – beim Zurückpendeln – eine neue Meldung.
        let dip = check(trip(busDelay: 4), memory: first.memory)
        #expect(dip.notices.isEmpty)
        #expect(check(trip(busDelay: 5), memory: dip.memory).notices.isEmpty)
    }

    @Test func shrinkingDelayIsReported() {
        let first = check(trip(busDelay: 20))
        let less = check(trip(busDelay: 8), memory: first.memory)
        #expect(less.notices.first?.body.contains("+8 min") == true)
    }

    @Test func belowThresholdIsQuiet() {
        #expect(check(trip(busDelay: 4)).notices.isEmpty)
        #expect(check(trip(busDelay: 4), settings: TripWatchSettings(delayThreshold: 3)).notices.count == 1)
    }

    @Test func platformChangeIsReportedOnce() {
        let first = check(trip(trainPlatform: "5"))
        #expect(first.notices.map(\.kind) == [.platformChange])
        #expect(first.notices[0].body.contains("Gleis 5 statt Gleis 2"))
        #expect(check(trip(trainPlatform: "5"), memory: first.memory).notices.isEmpty)
        #expect(check(trip(trainPlatform: "6"), memory: first.memory).notices.count == 1, "erneuter Wechsel")
    }

    @Test func cancellationWithReplacement() {
        let result = TripWatch.notices(for: trip(trainCancelled: true), replacement: trip(), title: "Zur Arbeit",
                                       now: t0 - 600, memory: .init(), settings: .init())
        #expect(result.notices.map(\.kind) == [.cancellation])
        #expect(result.notices[0].body.contains("Ersatz"))
        #expect(check(trip(trainCancelled: true), memory: result.memory).notices.isEmpty, "nur einmal")
    }

    @Test func missedAndTightConnections() {
        // Bus +17: an 32, S2 ab 30 → verpasst (Verspätung wird dann nicht extra gemeldet).
        let gone = check(trip(busDelay: 17))
        #expect(gone.notices.map(\.kind) == [.connection])
        #expect(gone.notices[0].body.contains("nicht zu schaffen"))

        // Bus +14: an 29, S2 ab 30 → 1 Minute (dazu die Verspätung).
        let tight = check(trip(busDelay: 14))
        #expect(tight.notices.map(\.kind) == [.connection, .delay])
        #expect(tight.notices[0].body.contains("1 Minute"))
        #expect(check(trip(busDelay: 14), memory: tight.memory).notices.isEmpty)
    }

    @Test func disabledKindsAreSkipped() {
        let settings = TripWatchSettings(enabledKinds: [.cancellation])
        #expect(check(trip(busDelay: 9, trainPlatform: "5"), settings: settings).notices.isEmpty)
    }
}

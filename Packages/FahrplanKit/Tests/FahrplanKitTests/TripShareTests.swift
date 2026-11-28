// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

@Suite struct TripShareTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    /// Sa., 28.11.2026, 18:36 Uhr in Berlin.
    private var start: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 18, minute: 36))!
    }

    private func stop(_ name: String, place: String? = nil, platform: String? = nil, dep: Double? = nil,
                      arr: Double? = nil, delay: Double = 0, cancelled: Bool = false) -> TripStop {
        func point(_ minutes: Double?) -> TimePoint? {
            minutes.map { TimePoint(scheduledTime: start + $0 * 60, realTime: start + $0 * 60 + delay * 60) }
        }
        return TripStop(stopID: name, name: name, place: place, platform: platform, arrival: point(arr),
                        departure: point(dep), isCancelled: cancelled, coordinate: nil)
    }

    private var trip: Trip {
        Trip(legs: [
            TripLeg(kind: .ride, mode: .suburbanRailway, line: "S1", stops: [
                stop("Bahnhof", place: "Pirna", platform: "1", dep: 0),
                stop("Hauptbahnhof", place: "Dresden", arr: 22),
            ]),
            TripLeg(kind: .walk, durationMinutes: 3),
            TripLeg(kind: .ride, mode: .tram, line: "7", stops: [
                stop("Hauptbahnhof", place: "Dresden", platform: "3", dep: 26, delay: 4),
                stop("Postplatz", place: "Dresden", arr: 31, delay: 4),
            ]),
        ], interchanges: 1)
    }

    @Test func sharesAReadableSummary() {
        #expect(trip.shareText(timeZone: berlin) == """
        Pirna Bahnhof → Dresden Postplatz
        Sa. 28. Nov. · 18:36–19:07 · 1 Umstieg

        S1  18:36 Pirna Bahnhof (Gl. 1) → 18:58 Dresden Hauptbahnhof
        7  19:02 (+4) Dresden Hauptbahnhof (Steig 3) → 19:07 (+4) Dresden Postplatz

        Gefunden mit Pendelfuchs · pendelfuchs.de
        """)
    }

    @Test func marksCancelledRidesAndDirectTrips() {
        let direct = Trip(legs: [TripLeg(kind: .ride, mode: .train, line: "RE 50", stops: [
            stop("Hbf", dep: 0, cancelled: true), stop("Leipzig Hbf", arr: 70, cancelled: true),
        ])], interchanges: 0)
        let text = direct.shareText(style: .nameOnly, timeZone: berlin)
        #expect(text.contains("ohne Umstieg"))
        #expect(text.contains("RE 50 fällt aus:  18:36 Hbf → 19:46 Leipzig Hbf"))
        #expect(Trip(legs: [], interchanges: 0).shareText() == "")
    }

    @Test func returnTripSwapsTheEnds() {
        let a = Stop(provider: .transitous, stopID: "a", name: "A")
        let b = Stop(provider: .transitous, stopID: "b", name: "B")
        let v = Stop(provider: .transitous, stopID: "v", name: "V")
        var options = TripOptions.standard
        options.maxTransfers = 1
        let query = TripQuery(origin: a, destination: b, via: v, time: start, isArrivalTime: true, options: options)
        let back = query.reversed(at: start + 3600)
        #expect(back.origin == b && back.destination == a && back.via == v)
        #expect(back.time == start + 3600 && !back.isArrivalTime)
        #expect(back.options == options, "Suchoptionen gelten auch für die Rückfahrt")
    }
}

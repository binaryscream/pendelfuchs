// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

@Suite struct StopNameTests {
    private func stop(_ name: String, _ place: String?) -> Stop {
        Stop(provider: .vvo, stopID: "1", name: name, place: place)
    }

    @Test func combinesPlaceAndName() {
        #expect(stop("Hbf", "Dresden").label(.withPlace) == "Dresden Hbf")
        #expect(stop("Bahnhof", "Pirna").label(.withPlace) == "Pirna Bahnhof")
        #expect(stop("Hauptbahnhof", "Dresden").label(.withPlace) == "Dresden Hauptbahnhof")
        #expect(stop("S-Bf. Großsedlitz", "Heidenau (Sachs)").label(.withPlace) == "Heidenau (Sachs) S-Bf. Großsedlitz")
    }

    @Test func doesNotRepeatThePlace() {
        #expect(stop("Dresden Hbf (Strehlener Str.)", "Dresden").label(.withPlace) == "Dresden Hbf (Strehlener Str.)")
        #expect(stop("Mühlbach (b Pirna) Bahnhof", "Pirna").label(.withPlace) == "Mühlbach (b Pirna) Bahnhof")
        #expect(stop("Leipzig", "Leipzig").label(.withPlace) == "Leipzig")
        #expect(stop("dresden hbf", "Dresden").label(.withPlace) == "dresden hbf")
    }

    @Test func withoutPlaceOrInNameOnlyMode() {
        #expect(stop("Hbf", nil).label(.withPlace) == "Hbf")
        #expect(stop("Hbf", "").label(.withPlace) == "Hbf")
        #expect(stop("Hbf", "Dresden").label(.nameOnly) == "Hbf")
    }

    @Test func secondaryLineOnlyInNameOnlyMode() {
        #expect(stop("Hbf", "Dresden").secondaryLine(.nameOnly) == "Dresden")
        #expect(stop("Hbf", "Dresden").secondaryLine(.withPlace) == nil)
        #expect(stop("Leipzig", "Leipzig").secondaryLine(.nameOnly) == nil)
        #expect(stop("Hbf", nil).secondaryLine(.nameOnly) == nil)
    }

    @Test func tripStopsAndTitles() {
        let tripStop = TripStop(stopID: "1", name: "Hbf", place: "Dresden", platform: nil, arrival: nil, departure: nil)
        #expect(tripStop.label(.withPlace) == "Dresden Hbf")
        #expect(tripStop.secondaryLine(.nameOnly) == "Dresden")

        let query = TripQuery(origin: stop("Bahnhof", "Pirna"), destination: stop("Hbf", "Dresden"))
        let leg = TripLeg(kind: .ride, mode: .train, line: "S1", stops: [
            TripStop(stopID: "a", name: "Bahnhof", place: "Pirna", platform: nil, arrival: nil,
                     departure: TimePoint(scheduledTime: .now)),
            TripStop(stopID: "b", name: "Hbf", place: "Dresden", platform: nil,
                     arrival: TimePoint(scheduledTime: .now.addingTimeInterval(1200)), departure: nil),
        ])
        let saved = SavedTrip(trip: Trip(legs: [leg], interchanges: 0), query: query)
        #expect(saved.title(style: .withPlace) == "Pirna Bahnhof → Dresden Hbf")
        #expect(saved.title(style: .nameOnly) == "Bahnhof → Hbf")

        let ride = TripActivityState(trip: Trip(legs: [leg], interchanges: 0)).rides[0]
        #expect(ride.fromLabel(.withPlace) == "Pirna Bahnhof")
        #expect(ride.toLabel(.nameOnly) == "Hbf")
    }

    @Test func oldActivityStatesWithoutPlaceStillDecode() throws {
        let json = """
        {"line":"S1","mode":"suburbanRailway","fromName":"Pirna","toName":"Hbf",
         "departure":{"scheduledTime":0},"arrival":{"scheduledTime":60},"isCancelled":false}
        """
        let ride = try JSONDecoder().decode(TripActivityState.Ride.self, from: Data(json.utf8))
        #expect(ride.fromPlace == nil)
        #expect(ride.fromLabel(.withPlace) == "Pirna")
    }

    @Test func tidiesAllCapsDestinations() {
        #expect("MESSE DRESDEN".tidiedCase == "Messe Dresden")
        #expect("BAD SCHANDAU-OSTRAU".tidiedCase == "Bad Schandau-Ostrau")
        #expect("TU DRESDEN HBF".tidiedCase == "TU Dresden HBF")
        // Gemischt geschriebene und kurze Namen bleiben unverändert.
        #expect("Wilder Mann".tidiedCase == "Wilder Mann")
        #expect("HBF".tidiedCase == "HBF")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

@Suite struct VVOTripsDecodingTests {
    private func trips() throws -> [Trip] {
        let url = try #require(Bundle.module.url(forResource: "trips-pirna-pirnaischer-platz", withExtension: "json",
                                                 subdirectory: "Fixtures"))
        return try VVODecoding.decode(TripsResponse.self, from: Data(contentsOf: url)).trips
    }

    @Test func decodesAllRoutesSorted() throws {
        let t = try trips()
        #expect(t.count == 5)
        #expect(t == t.sorted { $0.departure.expectedTime < $1.departure.expectedTime })
        #expect(Set(t.map(\.id)).count == t.count)
    }

    @Test func firstTripIsS2ThenTram12() throws {
        let trip = try #require(try trips().first { $0.rides.first?.line == "S2" })
        #expect(trip.rides.map(\.line) == ["S2", "12"])
        #expect(trip.rides.map(\.mode) == [.suburbanRailway, .tram])
        #expect(trip.interchanges == 1)
        #expect(trip.price == "6,30 €")
        #expect(trip.fareZones == "TZ Pirna (70), TZ Dresden (10)")

        let s2 = trip.rides[0]
        #expect(s2.stops.first?.name == "Bahnhof")
        #expect(s2.stops.first?.place == "Pirna")
        #expect(s2.stops.first?.platform == "2")
        #expect(s2.stops.last?.name == "S-Bf. Freiberger Straße")
        #expect(s2.departure?.realTime != nil)
        #expect(!s2.intermediateStops.isEmpty)
        #expect(s2.operatorName == "DB Regio AG Südost")
    }

    @Test func stairsAndFootpathsBecomeOneWalk() throws {
        let trip = try #require(try trips().first)
        // S-Bahn, Treppe + Fußweg (zusammengefasst), Straßenbahn
        #expect(trip.legs.map(\.kind) == [.ride, .walk, .ride])
        #expect(trip.legs[1].durationMinutes == 5)
    }

    @Test func durationMatchesFirstDepartureToLastArrival() throws {
        let trip = try #require(try trips().first)
        #expect(trip.duration == 39 * 60)
    }

    @Test func requestTimeUsesGermanLocalTime() {
        // 24.11.2026 05:30 UTC = 06:30 MEZ
        #expect(VVODecoding.requestTime(Date(timeIntervalSince1970: 1_795_498_200)) == "2026-11-24T06:30:00+01:00")
        // 1.7.2026 04:30 UTC = 06:30 MESZ
        #expect(VVODecoding.requestTime(Date(timeIntervalSince1970: 1_782_880_200)) == "2026-07-01T06:30:00+02:00")
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"))
struct VVOTripsLiveTests {
    let provider = VVOProvider()
    let pirna = Stop(provider: .vvo, stopID: "33003370", name: "Bahnhof", place: "Pirna")
    let pirnaischerPlatz = Stop(provider: .vvo, stopID: "33000005", name: "Pirnaischer Platz", place: "Dresden")
    let neustadt = Stop(provider: .vvo, stopID: "33000016", name: "Bahnhof Neustadt", place: "Dresden")

    @Test func findsTrips() async throws {
        let trips = try await provider.trips(TripQuery(origin: pirna, destination: pirnaischerPlatz))
        #expect(!trips.isEmpty)
    }

    @Test func viaIsRespected() async throws {
        let trips = try await provider.trips(TripQuery(origin: pirna, destination: pirnaischerPlatz, via: neustadt))
        #expect(!trips.isEmpty)
        for trip in trips {
            let passes = trip.rides.flatMap(\.stops).contains { $0.stopID == neustadt.stopID }
            #expect(passes, "Verbindung \(trip.id) führt nicht über Neustadt")
        }
    }

    @Test func arrivalTimeIsRespected() async throws {
        let target = Date.now.addingTimeInterval(3 * 3600)
        let trips = try await provider.trips(TripQuery(origin: pirna, destination: pirnaischerPlatz,
                                                       time: target, isArrivalTime: true))
        #expect(!trips.isEmpty)
        // Die API liefert ein Zeitfenster um die Wunschzeit – mindestens eine Verbindung muss rechtzeitig ankommen.
        #expect(trips.contains { $0.arrival.scheduledTime <= target.addingTimeInterval(60) })
        #expect(trips.allSatisfy { abs($0.arrival.scheduledTime.timeIntervalSince(target)) < 2 * 3600 })
    }
}

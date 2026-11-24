// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct TransitousDecodingTests {
    @Test func geocodeSplitsPlaceAndName() throws {
        let matches = try TransitousAPI.decode([TransitousAPI.Match].self, from: fixture("transitous-geocode-pirna"))
        let first = try #require(matches.first?.stop(distanceFrom: nil))
        #expect(first.provider == .transitous)
        #expect(first.stopID == "de-DELFI_de:14628:3370")
        #expect(first.name == "Bahnhof")
        #expect(first.place == "Pirna")
        #expect(first.displayName == "Pirna, Bahnhof")
        #expect(first.coordinate != nil)
    }

    @Test func reverseGeocodeGivesDistances() throws {
        let matches = try TransitousAPI.decode([TransitousAPI.Match].self, from: fixture("transitous-reverse-pirna"))
        let origin = Coordinate(latitude: 50.9624, longitude: 13.9290)
        let stops = matches.map { $0.stop(distanceFrom: origin) }
        #expect(stops.first?.stopID == "de-DELFI_de:14628:3370")
        #expect((stops.first?.distance ?? 999) < 50)
    }

    @Test func stoptimesBecomeDepartures() throws {
        let response = try TransitousAPI.decode(TransitousAPI.StopTimesResponse.self, from: fixture("transitous-stoptimes-hbf"))
        let deps = response.stopTimes.compactMap(\.departure)
        #expect(deps.count == response.stopTimes.count)
        #expect(deps.allSatisfy { $0.source == .transitous && !$0.line.isEmpty && $0.line != "?" })
        #expect(Set(deps.map(\.id)).count == deps.count)

        let tram = try #require(deps.first { $0.line == "10" && $0.direction == "Reick" })
        #expect(tram.mode == .tram)
        #expect(tram.hasRealTime)
        #expect(tram.platform == "1")

        let re = try #require(deps.first { $0.line == "RE50" })
        #expect(re.mode == .train)
        #expect(re.platform == "1", "„Gl. 1“ wird zu „1“")

        // Fehlender Kurzname → Anzeigename
        #expect(deps.contains { $0.line == "EuroNight 40457" })
        #expect(deps.contains { $0.mode == .coach }, "Fernbus")
        #expect(deps.contains { $0.mode == .longDistance }, "Nachtzug/Fernzug")
        #expect(deps.allSatisfy { $0.tripID != nil })

        let nightTrain = try #require(deps.first { $0.line == "NJ 457" })
        #expect(!nightTrain.hasRealTime)
        #expect(nightTrain.state == .unknown)
    }

    @Test func planBecomesTrips() throws {
        let response = try TransitousAPI.decode(TransitousAPI.PlanResponse.self, from: fixture("transitous-plan-pirna-postplatz"))
        let trips = response.itineraries.compactMap(\.trip)
        #expect(trips.count == 4)
        let trip = try #require(trips.first)
        #expect(trip.source == .transitous)
        #expect(trip.interchanges == 1)
        #expect(trip.legs.map(\.kind) == [.ride, .walk, .ride])
        #expect(trip.rides.map(\.line) == ["S1", "3"])
        #expect(trip.rides.map(\.mode) == [.suburbanRailway, .tram])
        #expect(trip.legs[1].durationMinutes == 3)
        #expect(trip.rides[0].stops.first?.platform == "1")
        #expect(trip.rides[0].stops.last?.name == "Dresden Hauptbahnhof")
        #expect(trip.rides[0].departure?.realTime != nil)
        #expect(trip.price == nil)
    }

    @Test func helpers() {
        #expect(TransitousAPI.platform("Gl. 5") == "5")
        #expect(TransitousAPI.platform("Gl.14") == "14")
        #expect(TransitousAPI.platform("Gleis 3a") == "3a")
        #expect(TransitousAPI.platform(" ") == nil)
        #expect(TransitousAPI.split(name: "Dresden Postplatz", place: "Dresden") == ("Postplatz", "Dresden"))
        #expect(TransitousAPI.split(name: "Bern, Bahnhof", place: "Bern") == ("Bahnhof", "Bern"))
        #expect(TransitousAPI.split(name: "Leipzig", place: "Leipzig") == ("Leipzig", nil))
        #expect(TransitousAPI.split(name: "Mühlbach (b Pirna) Bahnhof", place: "Pirna") == ("Mühlbach (b Pirna) Bahnhof", "Pirna"))
        #expect(TransitousAPI.parseDate("2026-11-23T21:10:00Z") == Date(timeIntervalSince1970: 1_795_468_200))
        #expect(TransitousAPI.parseDate("2026-11-23T21:10:00.500Z") != nil)
        #expect(TransitousAPI.mode("HIGHSPEED_RAIL") == .longDistance)
        #expect(TransitousAPI.mode("REGIONAL_RAIL") == .train)
        #expect(TransitousAPI.mode("SUBWAY") == .subway)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"))
struct TransitousLiveTests {
    let provider = TransitousProvider()

    @Test func searchFindsBerlinStop() async throws {
        await LiveThrottle.shared.wait()
        let stops = try await provider.searchStops(query: "Berlin Alexanderplatz")
        #expect(stops.contains { $0.stopID.hasPrefix("de-") })
    }

    @Test func nearbyFindsPirnaBahnhof() async throws {
        await LiveThrottle.shared.wait()
        let stops = try await provider.nearbyStops(around: Coordinate(latitude: 50.9624, longitude: 13.9290))
        #expect(stops.first?.stopID == "de-DELFI_de:14628:3370")
    }

    @Test func departuresAndTripsArrive() async throws {
        await LiveThrottle.shared.wait()
        let hbf = Stop(provider: .transitous, stopID: "de-DELFI_de:14612:28", name: "Hauptbahnhof", place: "Dresden")
        #expect(!(try await provider.departures(at: hbf, limit: 10)).isEmpty)

        let pirna = Stop(provider: .transitous, stopID: "de-DELFI_de:14628:3370", name: "Bahnhof", place: "Pirna")
        let leipzig = try #require(try await provider.searchStops(query: "Leipzig Hbf").first)
        let trips = try await provider.trips(TripQuery(origin: pirna, destination: leipzig))
        #expect(!trips.isEmpty)
    }

    @Test func viaIsRespected() async throws {
        await LiveThrottle.shared.wait()
        let pirna = Stop(provider: .transitous, stopID: "de-DELFI_de:14628:3370", name: "Bahnhof", place: "Pirna")
        let postplatz = Stop(provider: .transitous, stopID: "de-DELFI_de:14612:37:1:1", name: "Postplatz", place: "Dresden")
        let neustadt = try #require(try await provider.searchStops(query: "Dresden Bahnhof Neustadt").first)
        let trips = try await provider.trips(TripQuery(origin: pirna, destination: postplatz, via: neustadt))
        #expect(!trips.isEmpty)
        for trip in trips {
            #expect(trip.rides.flatMap(\.stops).contains { $0.name.contains("Neustadt") })
        }
    }
}

@Suite struct TransitousTrainNumberTests {
    @Test func extractsTrainNumbers() {
        #expect(TransitousAPI.trainNumber(tripShortName: "016536", mode: "REGIONAL_RAIL") == "16536")
        #expect(TransitousAPI.trainNumber(tripShortName: "ICE 597", mode: "HIGHSPEED_RAIL") == "597")
        #expect(TransitousAPI.trainNumber(tripShortName: "62", mode: "BUS") == nil)
        #expect(TransitousAPI.trainNumber(tripShortName: "", mode: "RAIL") == nil)
    }
}

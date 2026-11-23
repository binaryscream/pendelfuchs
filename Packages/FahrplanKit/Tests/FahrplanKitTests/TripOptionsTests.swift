// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func trip(_ modes: [TransportMode], transfers: Int? = nil) -> Trip {
    let t0 = Date(timeIntervalSince1970: 1_795_500_000)
    let legs = modes.enumerated().map { index, mode in
        TripLeg(kind: .ride, mode: mode, line: "\(index)", stops: [
            TripStop(stopID: "a", name: "A", place: nil, platform: nil, arrival: nil,
                     departure: TimePoint(scheduledTime: t0 + Double(index) * 600)),
            TripStop(stopID: "b", name: "B", place: nil, platform: nil,
                     arrival: TimePoint(scheduledTime: t0 + Double(index) * 600 + 300), departure: nil),
        ])
    }
    return Trip(legs: legs, interchanges: transfers ?? max(0, modes.count - 1))
}

@Suite struct TripOptionsTests {
    @Test func deutschlandTicketExcludesLongDistance() {
        let options = TripOptions(deutschlandTicketOnly: true)
        #expect(!options.allowedModes.contains(.longDistance))
        #expect(!options.allowedModes.contains(.coach))
        #expect(options.allows(trip([.suburbanRailway, .tram])))
        #expect(!options.allows(trip([.longDistance])))
        #expect(!options.allows(trip([.tram, .coach])))
    }

    @Test func maxTransfers() {
        let options = TripOptions(maxTransfers: 1)
        #expect(options.allows(trip([.train, .tram])))
        #expect(!options.allows(trip([.train, .tram, .cityBus])))
        #expect(TripOptions(maxTransfers: 0).allows(trip([.train])))
    }

    @Test func excludedModes() {
        let options = TripOptions(excludedModes: [.bus])
        #expect(!options.allows(trip([.train, .regionalBus])))
        #expect(options.allows(trip([.train, .tram])))
    }

    @Test func summary() {
        #expect(TripOptions().summary == "Alle Verkehrsmittel")
        #expect(TripOptions().isStandard)
        let options = TripOptions(deutschlandTicketOnly: true, maxTransfers: 1, walkingSpeed: .slow,
                                  excludedModes: [.bus, .longDistance])
        // Fernzug ist beim Deutschlandticket ohnehin ausgeschlossen und wird nicht doppelt genannt.
        #expect(options.summary == "Deutschlandticket · max. 1 Umstieg · Langsam gehen · ohne Bus")
    }

    @Test func providerParameters() {
        let dt = TripOptions(deutschlandTicketOnly: true).allowedModes
        let modes = TransitousAPI.transitModes(for: dt)
        #expect(modes.contains("REGIONAL_RAIL") && modes.contains("TRAM") && modes.contains("BUS"))
        #expect(!modes.contains("HIGHSPEED_RAIL") && !modes.contains("COACH"))
        let mots = VVODecoding.mots(for: TripOptions(excludedModes: [.bus]).allowedModes)
        #expect(mots.contains("Tram") && mots.contains("Train") && !mots.contains("CityBus"))
    }

    @Test func longDistanceNames() {
        #expect(TransportMode.isLongDistanceName("ICE 1650"))
        #expect(TransportMode.isLongDistanceName("IC 2048"))
        #expect(TransportMode.isLongDistanceName("EC 177"))
        #expect(!TransportMode.isLongDistanceName("RE50"))
        #expect(!TransportMode.isLongDistanceName("S1"))
        #expect(VVODecoding.mode("Train", line: "IC 2048") == .longDistance)
        #expect(VVODecoding.mode("Train", line: "RB71") == .train)
        #expect(TransitousAPI.lineName(displayName: "ICE 1650", routeShortName: "50", tripShortName: nil,
                                       mode: "HIGHSPEED_RAIL") == "ICE 1650")
        #expect(TransitousAPI.lineName(displayName: "RE50", routeShortName: "RE50", tripShortName: "016510",
                                       mode: "REGIONAL_RAIL") == "RE50")
    }
}

@Suite struct JourneyTests {
    @Test func vvoJourneyHasAllStopsAndPath() throws {
        let response = try VVODecoding.decode(JourneyResponse.self, from: fixture("vvo-dmtrip"))
        let leg = response.leg(line: "3", direction: "Coschütz", mode: .tram)
        #expect(leg.stops.count > 20)
        #expect(leg.stops.allSatisfy { $0.coordinate != nil })
        #expect(leg.path.count > 50)
        #expect(leg.stops.contains { $0.name.contains("Hauptbahnhof") })
        #expect(VVODecoding.dotNetDate(Date(timeIntervalSince1970: 1_795_470_720)) == "/Date(1795470720000-0000)/")
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"))
struct JourneyLiveTests {
    @Test func journeyFromBothSources() async throws {
        let hbfVVO = Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof", place: "Dresden")
        let vvo = VVOProvider()
        let vvoDeparture = try #require(try await vvo.departures(at: hbfVVO, limit: 3).first)
        let vvoLeg = try await vvo.journey(of: vvoDeparture, at: hbfVVO)
        #expect(vvoLeg.stops.count >= 2)

        let hbf = Stop(provider: .transitous, stopID: "de-DELFI_de:14612:28", name: "Hauptbahnhof", place: "Dresden")
        let transitous = TransitousProvider()
        let departure = try #require(try await transitous.departures(at: hbf, limit: 3).first)
        let leg = try await transitous.journey(of: departure, at: hbf)
        #expect(leg.stops.count >= 2)
        #expect(leg.line == departure.line)
    }

    @Test func deutschlandTicketFilterLive() async throws {
        let transitous = TransitousProvider()
        let dresden = Stop(provider: .transitous, stopID: "de-DELFI_de:14612:28", name: "Hauptbahnhof")
        let leipzig = try #require(try await transitous.searchStops(query: "Leipzig Hbf").first)
        let trips = try await transitous.trips(TripQuery(origin: dresden, destination: leipzig,
                                                         options: TripOptions(deutschlandTicketOnly: true)))
        #expect(!trips.isEmpty)
        #expect(trips.allSatisfy { $0.rides.allSatisfy { $0.mode?.isDeutschlandTicketValid ?? true } })
    }
}

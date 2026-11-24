// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct DBOccupancyTests {
    private var berlin: Calendar { DBWebClient.berlin }

    @Test func findsTheJourneyByLineAndTime() throws {
        let departure = berlin.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 7, minute: 6))!
        let id = try DBDecoding.journeyID(in: fixture("db-abfahrten-pirna"), line: "S1", departure: departure)
        #expect(id?.contains("ZE#S1") == true)
        #expect(try DBDecoding.journeyID(in: fixture("db-abfahrten-pirna"), line: "S2", departure: departure) == nil)
    }

    @Test func readsOccupancyPerStop() throws {
        let byName = try DBDecoding.occupancyByStop(from: fixture("db-fahrt-s1"))
        #expect(byName[DBDecoding.normalized("Pirna")] == .manySeats)
        #expect(byName[DBDecoding.normalized("Dresden Hbf")] == .fewSeats)
    }

    @Test func matchesStopNamesAcrossSources() throws {
        let byName = try DBDecoding.occupancyByStop(from: fixture("db-fahrt-s1"))
        let leg = TripLeg(kind: .ride, mode: .suburbanRailway, line: "S1", stops: [
            TripStop(stopID: "1", name: "Bahnhof", place: "Pirna", platform: nil, arrival: nil, departure: nil),
            TripStop(stopID: "2", name: "Hauptbahnhof", place: "Dresden", platform: nil, arrival: nil, departure: nil),
        ])
        let enriched = DBOccupancyProvider.apply(byName, to: leg)
        #expect(enriched.stops.map(\.occupancy) == [.manySeats, .fewSeats])
        #expect(enriched.boardingOccupancy == .manySeats)
    }
}

/// Echte Abfrage – nur mit `FAHRPLAN_LIVE_TESTS=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"))
struct DBOccupancyLiveTests {
    @Test func sBahnFromPirnaGetsOccupancy() async throws {
        await LiveThrottle.shared.wait()
        let trips = try await VVOProvider().trips(TripQuery(
            origin: Stop(provider: .vvo, stopID: "33003370", name: "Bahnhof", place: "Pirna"),
            destination: Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof", place: "Dresden"),
            // Tagsüber (nachts gibt es oft keine Prognose): morgen 8 Uhr.
            time: DBWebClient.berlin.date(bySettingHour: 8, minute: 0, second: 0,
                                          of: .now.addingTimeInterval(86_400))!))
        let leg = try #require(trips.flatMap(\.rides).first(where: DBOccupancyProvider.supports))
        let enriched = await DBOccupancyProvider().enrich(leg)
        #expect(enriched.stops.contains { $0.occupancy != nil })
    }
}

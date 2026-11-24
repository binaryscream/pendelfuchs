// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct CoachSequenceTests {
    @Test func decodesIntercityWithSectors() throws {
        let sequence = try #require(try DBDecoding.coachSequence(from: fixture("db-vehicle-sequence-ic")))
        #expect(sequence.platform == "12")
        #expect(sequence.sectors.map(\.name) == ["A", "B", "C", "D", "E", "F", "G"])
        #expect(sequence.coaches.count == 6)
        let first = sequence.coaches[0]
        #expect(first.number == "1" && first.kind == .controlCar && first.sector == "B")
        #expect(first.bikes && first.wheelchair && first.doubleDeck && !first.firstClass)
        #expect(sequence.coaches.contains { $0.firstClass && $0.number == "5" })
        #expect(sequence.coaches.last?.kind == .locomotive)
        #expect(sequence.destinations == ["Magdeburg Hbf"])
    }

    @Test func decodesSBahnWithoutSectors() throws {
        let sequence = try #require(try DBDecoding.coachSequence(from: fixture("db-vehicle-sequence-s2")))
        #expect(sequence.sectors.isEmpty)
        #expect(sequence.coaches.count == 3)
        #expect(sequence.coaches.map(\.start) == sequence.coaches.map(\.start).sorted())
        #expect(sequence.trainStart < sequence.trainEnd)
    }

    @Test func picksTheTrainStationNearby() throws {
        #expect(try DBDecoding.trainStation(from: fixture("db-orte-nearby-pirna")) == "8010272")
    }

    @Test func categoryFromLine() {
        #expect(DBCoachSequenceProvider.category(line: "S2", mode: .suburbanRailway) == "S")
        #expect(DBCoachSequenceProvider.category(line: "RB71", mode: .train) == "RB")
        #expect(DBCoachSequenceProvider.category(line: "ICE 905", mode: .longDistance) == "ICE")
        #expect(DBCoachSequenceProvider.category(line: nil, mode: .suburbanRailway) == "S")
    }
}

/// Echte Abfrage – nur mit `FAHRPLAN_LIVE_TESTS=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"))
struct CoachSequenceLiveTests {
    @Test func sBahnFromDresdenHasCoaches() async throws {
        await LiveThrottle.shared.wait()
        let vvo = VVOProvider()
        let trips = try await vvo.trips(TripQuery(
            origin: Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof", place: "Dresden"),
            destination: Stop(provider: .vvo, stopID: "33003370", name: "Bahnhof", place: "Pirna")))
        let leg = try #require(trips.flatMap(\.rides).first(where: DBCoachSequenceProvider.supports))
        let sequence = try await DBCoachSequenceProvider().coachSequence(for: leg)
        #expect(sequence?.coaches.isEmpty == false)
    }
}

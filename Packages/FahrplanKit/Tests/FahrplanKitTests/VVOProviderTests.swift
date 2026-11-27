// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Entfernung zweier Koordinaten in Metern (Haversine).
private func meters(_ a: Coordinate, _ b: Coordinate) -> Double {
    let r = 6_371_000.0
    let dLat = (b.latitude - a.latitude) * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let h = sin(dLat / 2) * sin(dLat / 2)
        + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(sqrt(h))
}

@Suite struct GaussKruegerTests {
    @Test func dresdenHauptbahnhofLandsWhereExpected() {
        // GK4-Koordinate der Haltestelle laut VVO-API, Bahnhof liegt bei ca. 51.0403 N / 13.7320 O.
        let c = GaussKrueger.toWGS84(.init(easting: 4_621_643, northing: 5_657_517))
        #expect(meters(c, Coordinate(latitude: 51.0403, longitude: 13.7320)) < 300)
    }

    @Test func roundTripIsLossless() {
        let original = Coordinate(latitude: 50.9625, longitude: 13.9442)
        let back = GaussKrueger.toWGS84(GaussKrueger.fromWGS84(original))
        #expect(meters(original, back) < 0.5)
    }
}

@Suite struct VVODecodingTests {
    /// Wie bei Transitous und TLMS: Der VVO soll die Anfragen der App zuordnen können.
    @Test func requestsCarryAppUserAgent() throws {
        let vvo = VVOProvider(userAgent: TransitousProvider.userAgent(version: "1.0"))
        let request = try vvo.request("/dm", body: ["stopid": "33000028"])
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Pendelfuchs/1.0 (+https://pendelfuchs.de)")
        #expect(request.httpMethod == "POST")
    }

    @Test func parsesDotNetDates() {
        let d = VVODecoding.parseDate(#"/Date(1795453020000-0000)/"#)
        #expect(d == Date(timeIntervalSince1970: 1_795_453_020))
        #expect(VVODecoding.parseDate(#"/Date(1795540293998+0100)/"#) == Date(timeIntervalSince1970: 1_795_540_293.998))
        #expect(VVODecoding.parseDate("Quatsch") == nil)
    }

    @Test func decodesDepartureMonitor() throws {
        let response = try VVODecoding.decode(DepartureMonitorResponse.self, from: fixture("dm-dresden-hbf"))
        let deps = response.departures
        #expect(deps.count == 14)
        #expect(deps == deps.sorted { $0.expectedTime < $1.expectedTime })
        #expect(deps.contains { $0.mode == .tram })
        #expect(deps.contains { $0.mode == .train })
        #expect(deps.contains { $0.state == .delayed && ($0.delayMinutes ?? 0) > 0 })
        #expect(deps.allSatisfy { !$0.line.isEmpty && !$0.direction.isEmpty })
        #expect(Set(deps.map(\.id)).count == deps.count, "IDs müssen eindeutig sein")
    }

    @Test func decodesStopSearch() throws {
        let response = try VVODecoding.decode(PointfinderResponse.self, from: fixture("pointfinder-hauptbahnhof"))
        let first = try #require(response.stops.first)
        #expect(first.stopID == "33000028")
        #expect(first.displayName == "Dresden, Hauptbahnhof")
        #expect(first.coordinate != nil)
    }

    @Test func nearbySearchSkipsAddressesAndKeepsDistance() throws {
        let response = try VVODecoding.decode(PointfinderResponse.self, from: fixture("pointfinder-coord-pirna"))
        let stops = response.stops
        #expect(stops.map(\.stopID) == ["33003370", "33003371", "33003382"])
        #expect(stops.first?.displayName == "Pirna, Bahnhof")
        #expect(stops.first?.distance == 72)
    }

    @Test func serviceErrorIsReported() {
        let data = Data(#"{"PointStatus":"NotIdentified","Status":{"Code":"ServiceError","Message":"no it connection"}}"#.utf8)
        #expect(throws: TransitError.self) {
            try VVODecoding.decode(PointfinderResponse.self, from: data)
        }
    }
}

/// Echte Netzwerkaufrufe – nur mit `FAHRPLAN_LIVE_TESTS=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"))
struct VVOLiveTests {
    let provider = VVOProvider()

    @Test func searchFindsPirna() async throws {
        await LiveThrottle.shared.wait()
        let stops = try await provider.searchStops(query: "Pirna Bahnhof")
        #expect(stops.contains { $0.stopID == "33003370" })
    }

    @Test func nearbyFromWGS84FindsPirnaBahnhof() async throws {
        await LiveThrottle.shared.wait()
        // Bahnhofsvorplatz Pirna
        let stops = try await provider.nearbyStops(around: Coordinate(latitude: 50.9624, longitude: 13.9290))
        #expect(stops.prefix(3).contains { $0.stopID == "33003370" })
    }

    @Test func departuresArrive() async throws {
        await LiveThrottle.shared.wait()
        let hbf = Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof")
        let deps = try await provider.departures(at: hbf, limit: 10)
        #expect(!deps.isEmpty)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"))
struct FullRunLiveTests {
    @Test func fullRunIsLongerThanTheTripSegment() async throws {
        await LiveThrottle.shared.wait()
        let vvo = VVOProvider()
        let origin = Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof", place: "Dresden")
        let destination = Stop(provider: .vvo, stopID: "33003370", name: "Bahnhof", place: "Pirna")
        let trips = try await vvo.trips(TripQuery(origin: origin, destination: destination, time: .now))
        let single = try #require(trips.first { $0.rides.count == 1 })
        let run = try #require(await vvo.fullRun(of: single))
        #expect(run.stops.count > single.rides[0].stops.count)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"))
struct FullRunRouterLiveTests {
    @Test func routerFindsFullRun() async throws {
        await LiveThrottle.shared.wait()
        let router = ProviderRouter(vvo: nil)
        let transitous = TransitousProvider()
        let origin = try #require(try await transitous.searchStops(query: "Dresden Hbf").first)
        await LiveThrottle.shared.wait()
        let destination = try #require(try await transitous.searchStops(query: "Pirna Bahnhof").first)
        await LiveThrottle.shared.wait()
        let trips = try await router.trips(TripQuery(origin: origin, destination: destination, time: .now))
        let single = try #require(trips.first { $0.rides.count == 1 })
        print("SRC", single.source as Any, single.rides[0].stops.first?.stopID as Any, single.rides[0].line as Any)
        let run = await router.fullRun(of: single)
        print("RUN", run?.stops.count as Any, run?.departure as Any, run?.arrival as Any, run?.stops.first as Any)
    }
}

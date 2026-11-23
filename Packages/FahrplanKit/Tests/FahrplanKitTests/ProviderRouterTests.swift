// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

@Suite struct ProviderRouterTests {
    @Test func mapsVVODistrictsToVVOIDs() {
        // Im Live-Test mit der VVO-API bestätigt (23.11.2026).
        #expect(ProviderRouter.vvoStopID(fromTransitousID: "de-DELFI_de:14628:3370") == "33003370")
        #expect(ProviderRouter.vvoStopID(fromTransitousID: "de-DELFI_de:14612:37:1:1") == "33000037")
        #expect(ProviderRouter.vvoStopID(fromTransitousID: "de-DELFI_de:14627:4000") == "33004000")
        #expect(ProviderRouter.vvoStopID(fromTransitousID: "de-DELFI_de:14625:7500:1:Gl.1") == "33007500")
    }

    @Test func leavesOtherRegionsAlone() {
        #expect(ProviderRouter.vvoStopID(fromTransitousID: "de-DELFI_de:11000:900100003") == nil, "Berlin")
        #expect(ProviderRouter.vvoStopID(fromTransitousID: "de-DELFI_de:14713:8000207") == nil, "Leipzig")
        #expect(ProviderRouter.vvoStopID(fromTransitousID: "cz-CZPTT_czptt:stop:DE:19433") == nil)
        #expect(ProviderRouter.vvoStopID(fromTransitousID: "de-DELFI_ch:1:sloid:7000") == nil)
    }

    @Test func convertsStopsOnlyWhenPossible() {
        let router = ProviderRouter()
        let pirna = Stop(provider: .transitous, stopID: "de-DELFI_de:14628:3370", name: "Bahnhof", place: "Pirna")
        #expect(router.asVVOStop(pirna)?.stopID == "33003370")
        #expect(router.asVVOStop(pirna)?.provider == .vvo)
        let berlin = Stop(provider: .transitous, stopID: "de-DELFI_de:11000:900100003", name: "Alexanderplatz")
        #expect(router.asVVOStop(berlin) == nil)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"))
struct ProviderRouterLiveTests {
    let pirna = Stop(provider: .transitous, stopID: "de-DELFI_de:14628:3370", name: "Bahnhof", place: "Pirna")
    let postplatz = Stop(provider: .transitous, stopID: "de-DELFI_de:14612:37:1:1", name: "Postplatz", place: "Dresden")

    @Test func usesVVOInsideVVOArea() async throws {
        let trips = try await ProviderRouter().trips(TripQuery(origin: pirna, destination: postplatz))
        #expect(trips.first?.source == .vvo)
        #expect(trips.first?.price != nil)
    }

    @Test func usesTransitousWhenVVODisabled() async throws {
        let router = ProviderRouter(vvo: nil)
        #expect(try await router.trips(TripQuery(origin: pirna, destination: postplatz)).first?.source == .transitous)
        #expect(try await router.departures(at: pirna, limit: 5).first?.source == .transitous)
    }

    @Test func oldVVOFavoritesWorkWithoutVVO() async throws {
        let vvoStop = Stop(provider: .vvo, stopID: "33003370", name: "Bahnhof", place: "Pirna")
        let deps = try await ProviderRouter(vvo: nil).departures(at: vvoStop, limit: 5)
        #expect(!deps.isEmpty)
        #expect(deps.allSatisfy { $0.source == .transitous })
    }

    @Test func leavesVVOAreaViaTransitous() async throws {
        let router = ProviderRouter()
        let leipzig = try #require(try await router.searchStops(query: "Leipzig Hbf").first)
        let trips = try await router.trips(TripQuery(origin: pirna, destination: leipzig))
        #expect(trips.first?.source == .transitous)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit
import TripKitBridge

@Suite struct RegionalNetworkTests {
    @Test func mapsDistrictsToNetworks() {
        #expect(RegionalNetwork.forDistrict("14511") == .vms)       // Chemnitz
        #expect(RegionalNetwork.forDistrict("14523") == .vvv)       // Vogtlandkreis
        #expect(RegionalNetwork.forDistrict("09162") == .bayern)    // München
        #expect(RegionalNetwork.forDistrict("08111") == .nvbw)      // Stuttgart
        #expect(RegionalNetwork.forDistrict("05315") == .nrw)       // Köln
        #expect(RegionalNetwork.forDistrict("13003") == .vmv)       // Rostock
        #expect(RegionalNetwork.forDistrict("14612") == nil, "VVO-Gebiet hat eine eigene Anbindung")
        #expect(RegionalNetwork.forDistrict("11000") == nil, "Berlin bräuchte eine Kennung (HAFAS)")
    }

    @Test func readsDHIDBehindAnyPrefix() {
        let pirna = DHID(transitousID: "de-DELFI_de:14628:3370:0:1")
        #expect(pirna?.district == "14628" && pirna?.number == "3370")
        #expect(DHID(transitousID: "at-Railway-Current-Reference-Data-2026_de:09162:100:11:11")?.district == "09162")
        #expect(DHID(transitousID: "be-sncb_8015485") == nil)
        #expect(DHID(transitousID: "at-Railway-Current-Reference-Data-2026_Pat:49:1349") == nil)
        // Auch große Bahnhöfe aus dem Bahn-Datensatz landen beim richtigen Verbund bzw. beim VVO.
        #expect(ProviderRouter.vvoStopID(fromTransitousID: "at-Railway-Current-Reference-Data-2026_de:14612:28:5:5")
                == "33000028")
    }

    @Test func findsNetworkForStops() {
        let munich = Stop(provider: .transitous, stopID: "de-DELFI_de:09162:6:40:81", name: "Hauptbahnhof", place: "München")
        #expect(RegionalNetwork.for(munich) == .bayern)
        let regional = Stop(provider: .nrw, stopID: "20009289", name: "Köln Hbf")
        #expect(RegionalNetwork.for(regional) == .nrw)
        let vvo = Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof", place: "Dresden")
        #expect(RegionalNetwork.for(vvo) == nil)
    }

    @Test func tripsWithUnplacedStopStillUseTheNetwork() {
        let router = ProviderRouter(vvo: nil)
        let chemnitz = Stop(provider: .transitous, stopID: "de-DELFI_de:14511:30062", name: "Chemnitz, Hauptbahnhof",
                            coordinate: Coordinate(latitude: 50.84, longitude: 12.93))
        let zwickauBus = Stop(provider: .transitous, stopID: "eu-flixbus_dcbdcbbd", name: "Zwickau, Hauptbahnhof",
                              coordinate: Coordinate(latitude: 50.72, longitude: 12.48))
        let berlin = Stop(provider: .transitous, stopID: "de-DELFI_de:11000:900003201", name: "Berlin Hbf",
                          coordinate: Coordinate(latitude: 52.52, longitude: 13.37))
        #expect(router.regionalForTrip(TripQuery(origin: chemnitz, destination: zwickauBus))?.network == .vms)
        #expect(router.regionalForTrip(TripQuery(origin: chemnitz, destination: berlin)) == nil)
        #expect(router.regionalForTrip(TripQuery(origin: zwickauBus, destination: zwickauBus)) == nil)
        #expect(ProviderRouter(vvo: nil, useRegional: false).regionalForTrip(TripQuery(origin: chemnitz, destination: zwickauBus)) == nil)
    }

    @Test func picksNearestCandidateWithMatchingName() {
        let wanted = Stop(provider: .transitous, stopID: "x", name: "Hauptbahnhof", place: "Chemnitz",
                          coordinate: Coordinate(latitude: 50.8405, longitude: 12.9306))
        let candidates = [
            Stop(provider: .vms, stopID: "1", name: "Chemnitz, Bahnhofstraße",
                 coordinate: Coordinate(latitude: 50.8401, longitude: 12.9300)),
            Stop(provider: .vms, stopID: "2", name: "Chemnitz Hauptbahnhof",
                 coordinate: Coordinate(latitude: 50.8398, longitude: 12.9310)),
            Stop(provider: .vms, stopID: "3", name: "Hauptbahnhof", place: "Zwickau",
                 coordinate: Coordinate(latitude: 50.7180, longitude: 12.4870)),
        ]
        #expect(RegionalProvider.bestMatch(for: wanted, in: candidates)?.stopID == "2")
    }
}

/// Echte Abfragen bei den Verbünden – nur mit `FAHRPLAN_LIVE_TESTS=1`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"), .serialized)
struct RegionalProviderLiveTests {
    /// Je Verbund: Start und Ziel als Transitous-Haltestellen (so kommen sie in der App an).
    static let cases: [(RegionalNetwork, String, String)] = [
        (.vms, "Chemnitz Hauptbahnhof", "Zwickau Hauptbahnhof"),
        (.vvv, "Plauen oberer Bahnhof", "Oelsnitz (Vogtl) Bahnhof"),
        (.bayern, "München Hbf", "Augsburg Hbf"),
        (.nvbw, "Stuttgart Hauptbahnhof", "Ulm Hbf"),
        (.nrw, "Köln Hbf", "Düsseldorf Hbf"),
        (.vmv, "Rostock Hbf", "Schwerin Hbf"),
    ]

    @Test(arguments: cases)
    func departuresTripsAndJourney(network: RegionalNetwork, from: String, to: String) async throws {
        let transitous = TransitousProvider()
        let origin = try #require(try await transitous.searchStops(query: from).first)
        let destination = try #require(try await transitous.searchStops(query: to).first)
        #expect(RegionalNetwork.for(origin) == network, "\(from): \(origin.stopID)")

        let regional = RegionalProvider(network: network)
        let departures = try await regional.departures(at: origin, limit: 10, from: nil)
        #expect(!departures.isEmpty, "\(network): keine Abfahrten")
        #expect(departures.allSatisfy { $0.source == network.providerID })

        if let withTrip = departures.first(where: { $0.tripID != nil }) {
            let leg = try await regional.journey(of: withTrip, at: origin)
            #expect(leg.stops.count >= 2, "\(network): Fahrtverlauf leer")
        }

        let trips = try await regional.trips(TripQuery(origin: origin, destination: destination))
        #expect(!trips.isEmpty, "\(network): keine Verbindungen")
        let first = try #require(trips.first)
        #expect(first.rides.first?.stops.count ?? 0 >= 2)
        print("\(network): \(departures.count) Abfahrten, z. B. \(departures[0].line) → \(departures[0].direction); "
              + "\(trips.count) Verbindungen, erste \(first.rides.map { $0.line ?? "?" }.joined(separator: ", ")), "
              + "Echtzeit: \(departures.contains { $0.realTime != nil })")
    }
}

@Suite struct RegionalFareTests {
    @Test func formatsSingleFare() {
        let vms = RegionalProvider.price(amount: 11.5, currency: "EUR", unitsName: nil, units: "VR")
        #expect(vms.price == "11,50 €")
        #expect(vms.zones == "Preisstufe VR")
        let vvv = RegionalProvider.price(amount: 5.6, currency: "EUR", unitsName: "Preisstufe", units: "13")
        #expect(vvv.zones == "Preisstufe 13")
        #expect(RegionalProvider.price(amount: 0, currency: "EUR", unitsName: nil, units: nil).price == nil)
    }
}

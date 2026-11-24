// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct PolylineTests {
    @Test func decodesGoogleReferenceExample() {
        // Beispiel aus der Google-Dokumentation (Genauigkeit 5).
        let points = Geo.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 5)
        #expect(points.count == 3)
        #expect(abs(points[0].latitude - 38.5) < 1e-6 && abs(points[0].longitude + 120.2) < 1e-6)
        #expect(abs(points[1].latitude - 40.7) < 1e-6 && abs(points[1].longitude + 120.95) < 1e-6)
        #expect(abs(points[2].latitude - 43.252) < 1e-6 && abs(points[2].longitude + 126.453) < 1e-6)
    }

    @Test func emptyInputGivesNoPoints() {
        #expect(Geo.decodePolyline("").isEmpty)
    }
}

@Suite struct TripProgressTests {
    let t0 = Date(timeIntervalSince1970: 1_795_497_780)

    /// Drei Halte auf einer Linie nach Osten: 0 min, 10 min (an 9, ab 10), 20 min.
    private var leg: TripLeg {
        func stop(_ name: String, lon: Double, arr: Double?, dep: Double?) -> TripStop {
            TripStop(stopID: name, name: name, place: nil, platform: nil,
                     arrival: arr.map { TimePoint(scheduledTime: t0 + $0 * 60) },
                     departure: dep.map { TimePoint(scheduledTime: t0 + $0 * 60) },
                     coordinate: Coordinate(latitude: 51, longitude: lon))
        }
        return TripLeg(kind: .ride, mode: .tram, line: "7", stops: [
            stop("A", lon: 13.70, arr: nil, dep: 0),
            stop("B", lon: 13.80, arr: 9, dep: 10),
            stop("C", lon: 13.90, arr: 20, dep: nil),
        ])
    }

    @Test func progressFollowsTheClock() {
        #expect(leg.progress(at: t0 - 60) == .notStarted)
        #expect(leg.progress(at: t0 + 25 * 60) == .finished)
        guard case .underway(let passed, let fraction) = leg.progress(at: t0 + 4.5 * 60) else {
            Issue.record("sollte unterwegs sein"); return
        }
        #expect(passed == 0)
        #expect(abs(fraction - 0.5) < 0.01, "Hälfte der Fahrzeit bis zur Ankunft an B")
        #expect(leg.progress(at: t0 + 15 * 60) == .underway(passed: 1, fraction: 0.5))
        #expect(leg.progress(at: t0 + 15 * 60).hasPassed(1))
        #expect(!leg.progress(at: t0 + 15 * 60).hasPassed(2))
    }

    @Test func estimatedPositionLiesBetweenStops() throws {
        let position = try #require(leg.estimatedPosition(at: t0 + 15 * 60))
        #expect(abs(position.longitude - 13.85) < 0.001)
        #expect(leg.estimatedPosition(at: t0 - 60) == nil)
    }

    @Test func overallProgress() {
        let trip = Trip(legs: [leg], interchanges: 0)
        #expect(trip.overallProgress(at: t0 - 60) == nil)
        #expect(trip.overallProgress(at: t0 + 10 * 60) == 0.5)
        #expect(trip.overallProgress(at: t0 + 60 * 60) == 1)
    }
}

@Suite struct RouteGeometryTests {
    @Test func transitousLegsHavePathAndStopCoordinates() throws {
        let response = try TransitousAPI.decode(TransitousAPI.PlanResponse.self, from: fixture("transitous-plan-geometry"))
        let trip = try #require(response.itineraries.first?.trip)
        for ride in trip.rides {
            #expect(ride.path.count > 10)
            #expect(ride.stops.allSatisfy { $0.coordinate != nil })
            // Strecke beginnt am Einstiegshalt
            let start = try #require(ride.stops.first?.coordinate)
            #expect(Geo.meters(start, ride.path[0]) < 300)
        }
    }

    @Test func vvoLegsHavePathFromMapData() throws {
        let trips = try VVODecoding.decode(TripsResponse.self, from: fixture("vvo-trips-mapdata")).trips
        let trip = try #require(trips.first)
        for ride in trip.rides {
            #expect(ride.path.count > 10)
            let start = try #require(ride.stops.first?.coordinate)
            #expect(Geo.meters(start, ride.path[0]) < 300, "GK4 → WGS84 muss zur Haltestelle passen")
            // Pirna/Dresden liegen grob bei 51° N / 13.7–13.95° O
            #expect(ride.path.allSatisfy { (50.8...51.2).contains($0.latitude) && (13.6...14.1).contains($0.longitude) })
        }
    }

    @Test func guaranteedConnectionBecomesNote() throws {
        let json = """
        {"Status":{"Code":"Ok"},"Routes":[{"Interchanges":1,"PartialRoutes":[
          {"Mot":{"Type":"CityBus","Name":"65"},"RegularStops":[
            {"Name":"A","DataId":"1","DepartureTime":"/Date(1795500000000-0000)/"},
            {"Name":"Altleuben","DataId":"2","ArrivalTime":"/Date(1795500600000-0000)/"}]},
          {"Duration":3,"Mot":{"Type":"StayForConnection","Name":"gesicherter Anschluss"},"RegularStops":[
            {"Name":"Altleuben","DataId":"2"},{"Name":"Altleuben","DataId":"2"}]},
          {"Mot":{"Type":"CityBus","Name":"65"},"RegularStops":[
            {"Name":"Altleuben","DataId":"2","DepartureTime":"/Date(1795500780000-0000)/"},
            {"Name":"B","DataId":"3","ArrivalTime":"/Date(1795501200000-0000)/"}]}]}]}
        """
        let trip = try #require(try VVODecoding.decode(TripsResponse.self, from: Data(json.utf8)).trips.first)
        #expect(trip.rides.map(\.line) == ["65", "65"])
        #expect(trip.rides[1].notes.first == "Anschluss wird abgewartet")
    }

    @Test func replacementBusIsKeptAsBusWithNote() throws {
        let json = """
        {"Status":{"Code":"Ok"},"Routes":[{"Interchanges":0,"PartialRoutes":[
          {"Duration":2,"Mot":{"Type":"Footpath","Name":"Fussweg"}},
          {"Mot":{"Type":"Bus","Name":"SEV S1","ProductName":"Ersatzverkehr","Direction":"Dresden Hbf"},"RegularStops":[
            {"Name":"ZOB / Bahnhof","DataId":"1","DepartureTime":"/Date(1795500000000-0000)/"},
            {"Name":"Pechhütte","DataId":"2","ArrivalTime":"/Date(1795500600000-0000)/","DepartureTime":"/Date(1795500660000-0000)/"},
            {"Name":"Dobritz","DataId":"3","ArrivalTime":"/Date(1795501200000-0000)/"}]}]}]}
        """
        let trip = try #require(try VVODecoding.decode(TripsResponse.self, from: Data(json.utf8)).trips.first)
        let ride = try #require(trip.rides.first)
        #expect(ride.line == "SEV S1")
        #expect(ride.mode == .regionalBus)
        #expect(ride.notes.contains("Schienenersatzverkehr"))
        #expect(TripOptions(deutschlandTicketOnly: true).allows(trip), "SEV muss beim Deutschlandticket erscheinen")
    }

    @Test func mapDataParsing() {
        let path = VVODecoding.path(fromMapData: "Tram|5657517|4621643|5659228|4620896")
        #expect(path.count == 2)
        #expect(VVODecoding.path(fromMapData: "Footpath|").isEmpty)
    }
}

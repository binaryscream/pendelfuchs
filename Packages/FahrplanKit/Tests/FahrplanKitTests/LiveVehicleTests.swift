// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

@Suite struct LiveVehicleTests {
    let t0 = Date(timeIntervalSince1970: 1_795_621_000)

    /// Straßenbahn 3 in Dresden nach Osten: A (0 min) – B (5 min) – C (10 min), je ca. 2,8 km.
    private func leg(line: String = "3", mode: TransportMode = .tram, delay: Double = 0) -> TripLeg {
        func stop(_ name: String, lon: Double, minutes: Double, last: Bool = false) -> TripStop {
            let time = TimePoint(scheduledTime: t0 + minutes * 60, realTime: t0 + minutes * 60 + delay)
            return TripStop(stopID: name, name: name, place: nil, platform: nil,
                            arrival: minutes > 0 ? time : nil, departure: last ? nil : time,
                            coordinate: Coordinate(latitude: 51.05, longitude: lon))
        }
        return TripLeg(kind: .ride, mode: mode, line: line, stops: [
            stop("A", lon: 13.70, minutes: 0),
            stop("B", lon: 13.74, minutes: 5),
            stop("C", lon: 13.78, minutes: 10, last: true),
        ])
    }

    private func vehicle(line: Int = 3, run: Int, lon: Double, lat: Double = 51.05, at: Date, delay: Double? = nil)
        -> LiveVehicle {
        LiveVehicle(line: line, run: run, coordinate: Coordinate(latitude: lat, longitude: lon), reportedAt: at,
                    delay: delay)
    }

    @Test func decodesLizardWaypoints() throws {
        let json = """
        [{"id":0,"source":"R09Telegram","time":1795621322658,"region":0,"lat":51.0696,"lon":13.7378,
          "line":3,"run":1,"delayed":60.0,"r09_reporting_point":56045,"r09_destination_number":493},
         {"id":0,"source":"R09Telegram","time":1795621322658,"region":0,"lat":51.0,"lon":13.7}]
        """
        let vehicles = try TLMSClient.decode(Data(json.utf8))
        #expect(vehicles.count == 1, "Einträge ohne Linie/Umlauf werden übersprungen")
        #expect(vehicles[0].line == 3 && vehicles[0].run == 1 && vehicles[0].delay == 60)
        #expect(abs(vehicles[0].reportedAt.timeIntervalSince1970 - 1_795_621_322.658) < 0.001)
    }

    @Test func onlyDresdenTramsAndCityBusesAreEligible() {
        #expect(leg().tlmsLine == 3)
        #expect(leg(line: "62", mode: .cityBus).tlmsLine == 62)
        #expect(leg(line: "S1", mode: .suburbanRailway).tlmsLine == nil)
        #expect(leg(line: "EV3", mode: .cityBus).tlmsLine == nil)
        var pirna = leg(line: "A", mode: .regionalBus)
        #expect(pirna.tlmsLine == nil)
        pirna = leg()
        for index in pirna.stops.indices { pirna.stops[index].coordinate?.latitude = 50.96 + 0.3 }
        #expect(pirna.tlmsLine == nil, "außerhalb von Dresden")
    }

    @Test func picksTheVehicleNearTheExpectedPosition() throws {
        let now = t0 + 150 // halbe Strecke A–B ≈ 13.72
        let vehicles = [
            vehicle(run: 9, lon: 13.775, at: now - 20),            // gleiche Linie, aber weit voraus
            vehicle(line: 4, run: 1, lon: 13.721, at: now - 20),   // andere Linie
            vehicle(run: 5, lon: 13.718, lat: 51.06, at: now - 20), // abseits der Strecke
            vehicle(run: 2, lon: 13.716, at: now - 20),
        ]
        let match = try #require(leg().liveMatch(in: vehicles, at: now))
        #expect(match.vehicle.run == 2)
        #expect(leg().liveMatch(in: [vehicle(run: 2, lon: 13.716, at: now - 600)], at: now) == nil,
                "zu alte Meldungen zählen nicht")
    }

    @Test func similarDelayBreaksTies() throws {
        let now = t0 + 150
        let vehicles = [
            vehicle(run: 1, lon: 13.719, at: now - 10, delay: 0),
            vehicle(run: 2, lon: 13.721, at: now - 10, delay: 240),
        ]
        #expect(leg(delay: 240).liveMatch(in: vehicles, at: now)?.vehicle.run == 2)
        #expect(leg(delay: 0).liveMatch(in: vehicles, at: now)?.vehicle.run == 1)
    }

    @Test func keepsThePreferredVehicle() {
        let now = t0 + 150
        let vehicles = [vehicle(run: 1, lon: 13.720, at: now - 10), vehicle(run: 2, lon: 13.735, at: now - 10)]
        #expect(leg().liveMatch(in: vehicles, at: now)?.vehicle.run == 1)
        #expect(leg().liveMatch(in: vehicles, at: now, preferredRun: 2)?.vehicle.run == 2)
    }

    @Test func usesOnlyTheNewestReportPerVehicle() throws {
        let now = t0 + 150
        let vehicles = [
            vehicle(run: 1, lon: 13.735, at: now - 10),   // neueste Meldung von Umlauf 1
            vehicle(run: 1, lon: 13.716, at: now - 170),  // ältere Meldung, passt scheinbar besser
        ]
        let match = try #require(leg().liveMatch(in: vehicles, at: now, preferredRun: 1))
        #expect(match.vehicle.reportedAt == now - 10)
    }

    @Test func noMatchOutsideTheRideTime() {
        let vehicles = [vehicle(run: 1, lon: 13.70, at: t0 - 3600)]
        #expect(leg().liveMatch(in: vehicles, at: t0 - 3600) == nil)
    }

    @Test func livePositionMovesOnButStopsAtTheNextStop() throws {
        let reported = t0 + 60
        let match = try #require(leg().liveMatch(in: [vehicle(run: 1, lon: 13.71, at: reported)], at: reported))
        let soon = try #require(leg().livePosition(of: match, at: reported + 30))
        #expect(soon.longitude > 13.71 && soon.longitude < 13.74, "rückt weiter, aber nicht über B hinaus")
        // Fahrplan: 0,04° in 300 s → 30 s ≈ 0,004°.
        #expect(abs(soon.longitude - 13.714) < 0.001)
        let late = try #require(leg().livePosition(of: match, at: reported + 600))
        #expect(abs(late.longitude - 13.74) < 0.0005, "wartet am nächsten Halt")
    }
}

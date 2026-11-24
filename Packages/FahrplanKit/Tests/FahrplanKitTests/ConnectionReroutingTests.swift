// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private let berlin: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func at(_ hour: Int, _ minute: Int) -> Date {
    berlin.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour, minute: minute))!
}

/// Fahrt von `dep` bis `arr`; `delay` verspätet die Ankunft in Minuten.
private func ride(_ line: String, _ dep: Date, _ arr: Date, arrivalDelay: Double = 0) -> TripLeg {
    TripLeg(kind: .ride, mode: .cityBus, line: line, stops: [
        TripStop(stopID: "a", name: "A", place: nil, platform: nil, arrival: nil, departure: TimePoint(scheduledTime: dep)),
        TripStop(stopID: "b", name: "B", place: nil, platform: nil,
                 arrival: TimePoint(scheduledTime: arr, realTime: arrivalDelay == 0 ? nil : arr.addingTimeInterval(arrivalDelay * 60)),
                 departure: nil),
    ])
}

private let origin = Stop(provider: .vvo, stopID: "1", name: "Start", place: "Pirna")
private let target = Stop(provider: .vvo, stopID: "2", name: "Ziel", place: "Dresden")


@Suite struct ConnectionReroutingTests {
    private func saved() -> SavedTrip {
        SavedTrip(trip: Trip(legs: [ride("86", at(6, 30), at(6, 45)), ride("S2", at(6, 50), at(7, 10))], interchanges: 1),
                  query: TripQuery(origin: origin, destination: target, time: at(6, 30)),
                  weekdays: Weekday.workdays, calendar: berlin)
    }

    private func trip(busDelay: Double, trainAt: Int, trainDelay: Double = 0, hour: Int = 6) -> Trip {
        var train = ride("S2", at(hour, trainAt), at(hour + 1, 10))
        if trainDelay != 0 { train.stops[0].departure?.realTime = at(hour, trainAt).addingTimeInterval(trainDelay * 60) }
        return Trip(legs: [ride("86", at(6, 30), at(6, 45), arrivalDelay: busDelay), train], interchanges: 1)
    }

    @Test func detectsMissedConnection() {
        let missed = trip(busDelay: 8, trainAt: 50)      // Bus kommt 6:53, Zug fährt 6:50
        guard case .connectionMissed(let line, _) = missed.disruption else {
            Issue.record("Anschluss sollte als verpasst erkannt werden"); return
        }
        #expect(line == "S2")
        #expect(trip(busDelay: 3, trainAt: 50).disruption == nil)
        #expect(missed.overallProgress(at: at(6, 40)) == nil)
    }

    @Test func keepsTheTripWhenConnectionHolds() throws {
        let ok = trip(busDelay: 2, trainAt: 50)
        let resolved = try #require(saved().resolve(in: [ok], now: at(6, 20), calendar: berlin))
        #expect(resolved.note == nil)
        #expect(resolved.trip.id == ok.id)
    }

    @Test func switchesToNextTrainWithSameBus() throws {
        let broken = trip(busDelay: 8, trainAt: 50)
        let nextTrain = trip(busDelay: 8, trainAt: 59)   // gleicher Bus, spätere S2
        let resolved = try #require(saved().resolve(in: [broken, nextTrain], now: at(6, 35), calendar: berlin))
        #expect(resolved.trip.rides[1].departure?.scheduledTime == at(6, 59))
        #expect(resolved.note?.contains("verpasst") == true)
    }

    @Test func switchesToNextDepartureBeforeStarting() throws {
        // Erste Fahrt fällt aus, noch nicht losgefahren → nächste Abfahrt (7:00 Bus 86).
        var cancelled = trip(busDelay: 0, trainAt: 50)
        for i in cancelled.legs[0].stops.indices { cancelled.legs[0].stops[i].isCancelled = true }
        let later = Trip(legs: [ride("86", at(7, 0), at(7, 15)), ride("S2", at(7, 20), at(7, 40))], interchanges: 1)
        let resolved = try #require(saved().resolve(in: [cancelled, later], now: at(6, 0), calendar: berlin))
        #expect(resolved.trip.departure.scheduledTime == at(7, 0))
        #expect(resolved.note?.contains("fällt aus") == true)
    }

    @Test func doesNotJumpToLaterBusOnceUnderway() throws {
        // Man sitzt schon im 6:30-Bus; ein 7:00-Bus hilft nicht mehr, es bleibt bei der verpassten Verbindung.
        let broken = trip(busDelay: 8, trainAt: 50)
        let later = Trip(legs: [ride("86", at(7, 0), at(7, 15)), ride("S2", at(7, 20), at(7, 40))], interchanges: 1)
        let resolved = try #require(saved().resolve(in: [broken, later], now: at(6, 35), calendar: berlin))
        #expect(resolved.trip.id == broken.id)
        #expect(resolved.note == nil)
    }
}

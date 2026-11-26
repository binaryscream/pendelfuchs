// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private let berlin: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

/// 23.11.2026 ist ein Montag.
private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    berlin.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func ride(_ line: String, from dep: Date, to arr: Date) -> TripLeg {
    TripLeg(kind: .ride, mode: .suburbanRailway, line: line, stops: [
        TripStop(stopID: "a", name: "A", place: nil, platform: nil, arrival: nil, departure: TimePoint(scheduledTime: dep)),
        TripStop(stopID: "b", name: "B", place: nil, platform: nil, arrival: TimePoint(scheduledTime: arr), departure: nil),
    ])
}

private let pirna = Stop(provider: .vvo, stopID: "33003370", name: "Bahnhof", place: "Pirna", distance: 30)
private let postplatz = Stop(provider: .vvo, stopID: "33000037", name: "Postplatz", place: "Dresden")

private func trip(_ lines: [String], at dep: Date) -> Trip {
    var legs: [TripLeg] = []
    var t = dep
    for line in lines {
        legs.append(ride(line, from: t, to: t.addingTimeInterval(15 * 60)))
        t = t.addingTimeInterval(20 * 60)
    }
    return Trip(legs: legs, interchanges: lines.count - 1)
}

@Suite struct WeekdayTests {
    @Test func mapsCalendarWeekdays() {
        #expect(Weekday(date: date(23, 12, 0), calendar: berlin) == .monday)
        #expect(Weekday(date: date(29, 12, 0), calendar: berlin) == .sunday)
        #expect(Weekday.allCases.first == .monday && Weekday.allCases.last == .sunday)
    }

    @Test func summaries() {
        #expect(Set<Weekday>().summary == "Nicht regelmäßig")
        #expect(Weekday.workdays.summary == "Mo–Fr")
        #expect(Weekday.everyDay.summary == "Täglich")
        #expect(Weekday.weekend.summary == "Wochenende")
        #expect(Set([Weekday.monday, .wednesday, .friday]).summary == "Mo, Mi, Fr")
        #expect(Set([Weekday.monday, .wednesday, .thursday, .friday]).summary == "Mo, Mi–Fr")
        #expect(Set([Weekday.saturday, .sunday, .monday]).summary == "Mo, Sa, So")
    }
}

@Suite struct SavedTripTests {
    let query = TripQuery(origin: pirna, destination: postplatz)

    private func saved(_ weekdays: Set<Weekday>, at hour: Int = 6, _ minute: Int = 30) -> SavedTrip {
        SavedTrip(trip: trip(["S1", "7"], at: date(23, hour, minute)), query: query, weekdays: weekdays, calendar: berlin)
    }

    @Test func capturesTripDetails() {
        let s = saved(Weekday.workdays)
        #expect(s.departure == TimeOfDay(hour: 6, minute: 30))
        #expect(s.lines == ["S1", "7"])
        #expect(s.origin.distance == nil, "Entfernung aus der Umkreissuche darf nicht mitgespeichert werden")
        #expect(s.title == "Pirna Bahnhof → Dresden Postplatz")
        #expect(s.title(style: .nameOnly) == "Bahnhof → Postplatz")
        #expect(s.isRegular)
    }

    @Test func nextOccurrenceLaterToday() {
        // Montag 05:00 → heute 06:30
        #expect(saved(Weekday.workdays).nextOccurrence(after: date(23, 5, 0), calendar: berlin) == date(23, 6, 30))
    }

    @Test func nextOccurrenceKeepsJustDepartedTrip() {
        // Montag 06:40 → die 06:30-Fahrt ist noch innerhalb der Kulanzzeit
        #expect(saved(Weekday.workdays).nextOccurrence(after: date(23, 6, 40), calendar: berlin) == date(23, 6, 30))
    }

    @Test func nextOccurrenceSkipsToNextWeekday() {
        // Freitag 27.11. 08:00 → Montag 30.11. 06:30 (Wochenende übersprungen)
        #expect(saved(Weekday.workdays).nextOccurrence(after: date(27, 8, 0), calendar: berlin) == date(30, 6, 30))
    }

    @Test func nextOccurrenceSameWeekdayNextWeek() {
        // Nur montags, Montag 09:00 → Montag darauf
        #expect(saved([.monday]).nextOccurrence(after: date(23, 9, 0), calendar: berlin) == date(30, 6, 30))
    }

    @Test func nextOccurrenceKeepsTripAcrossMidnight() {
        // Montag 23:50 abgefahren, jetzt Dienstag 00:05 → gilt innerhalb der Kulanzzeit noch als aktuell
        let late = saved(Weekday.workdays, at: 23, 50)
        #expect(late.nextOccurrence(after: date(24, 0, 5), calendar: berlin) == date(23, 23, 50))
        // … danach ist der Dienstagabend dran.
        #expect(late.nextOccurrence(after: date(24, 0, 30), calendar: berlin) == date(24, 23, 50))
    }

    @Test func replacementSurvivesDepartureTimeOfCancelledRide() throws {
        // S1 um 06:30 fällt aus, Ersatz 06:40. Auch um 06:35 (nach der geplanten Abfahrt) gilt der Ersatz.
        let s = SavedTrip(trip: trip(["S1"], at: date(23, 6, 30)), query: query, weekdays: Weekday.workdays, calendar: berlin)
        var cancelled = trip(["S1"], at: date(23, 6, 30))
        for index in cancelled.legs[0].stops.indices { cancelled.legs[0].stops[index].isCancelled = true }
        let next = trip(["S1"], at: date(23, 6, 40))
        let resolved = try #require(s.resolve(in: [cancelled, next], now: date(23, 6, 35), calendar: berlin))
        #expect(resolved.trip.id == next.id)
        #expect(resolved.note != nil)
    }

    @Test func skippedIntermediateStopDoesNotMakeRideUnusable() {
        var leg = TripLeg(kind: .ride, mode: .tram, line: "7", stops: ["a", "b", "c"].map {
            TripStop(stopID: $0, name: $0, place: nil, platform: nil, arrival: TimePoint(scheduledTime: date(23, 6, 0)),
                     departure: TimePoint(scheduledTime: date(23, 6, 0)))
        })
        leg.stops[1].isCancelled = true
        #expect(leg.isCancelled)
        #expect(!leg.isUnusable)
        #expect(!TripActivityState(trip: Trip(legs: [leg], interchanges: 0)).isCancelled)
        leg.stops[0].isCancelled = true
        #expect(leg.isUnusable)
    }

    @Test func queryStartsABitBeforeTheSavedDeparture() {
        // 06:30 gemerkt → Suche ab 06:25, damit ein Fußweg davor oder eine vorgezogene Minute nicht stört.
        #expect(saved(Weekday.workdays).query(on: date(24, 12, 0), calendar: berlin).time == date(24, 6, 25))
    }

    @Test func progressSurvivesMissingRealTimeAtLaterStops() {
        // 10 min Verspätung, aber nur der erste Halt hat Echtzeit: Um 06:20 (Plan-Ankunft 06:15) fährt sie noch.
        var leg = ride("S1", from: date(23, 6, 0), to: date(23, 6, 15))
        leg.stops[0].departure?.realTime = date(23, 6, 25)
        #expect(leg.progress(at: date(23, 6, 20)) == .notStarted)
        #expect(leg.progress(at: date(23, 6, 24)) != .finished)
    }

    @Test func longTripsKeepTheirRealArrivalInTheActivity() {
        let long = trip(["1", "2", "3", "4", "5", "6", "7"], at: date(23, 6, 0))
        let state = TripActivityState(trip: long)
        #expect(state.rides.count == 5)
        #expect(state.arrival.scheduledTime == long.arrival.scheduledTime)
    }

    @Test func bookmarkHasNoOccurrence() {
        #expect(saved([]).nextOccurrence(after: date(23, 5, 0), calendar: berlin) == nil)
    }

    @Test func recognisesSameTrip() {
        let s = saved([])
        #expect(s.isSame(as: trip(["S1", "7"], at: date(25, 6, 30)), query: query, calendar: berlin))
        #expect(!s.isSame(as: trip(["S1", "7"], at: date(25, 6, 36)), query: query, calendar: berlin))
        #expect(!s.isSame(as: trip(["S2", "7"], at: date(25, 6, 30)), query: query, calendar: berlin))
    }

    @Test func bestMatchPrefersExactTrip() {
        let s = saved(Weekday.workdays)
        let candidates = [
            trip(["S2", "12"], at: date(24, 6, 23)),
            trip(["S1", "7"], at: date(24, 6, 31)),
            trip(["S1", "68"], at: date(24, 6, 30)),
        ]
        #expect(s.bestMatch(in: candidates, calendar: berlin)?.rides.map(\.line) == ["S1", "7"])
    }

    @Test func bestMatchToleratesTimetableChange() {
        // Fahrplanwechsel: S1 fährt jetzt 06:34 und man steigt in die 68 um
        let s = saved(Weekday.workdays)
        let candidates = [trip(["S2", "12"], at: date(24, 6, 23)), trip(["S1", "68"], at: date(24, 6, 34))]
        #expect(s.bestMatch(in: candidates, calendar: berlin)?.rides.map(\.line) == ["S1", "68"])
        #expect(s.bestMatch(in: [trip(["S1", "7"], at: date(24, 7, 30))], calendar: berlin) == nil)
    }
}

@MainActor
@Suite struct SavedTripsStoreTests {
    @Test func persistsAndSorts() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SavedTripsStore(defaults: defaults)
        let query = TripQuery(origin: pirna, destination: postplatz)
        let a = store.add(trip(["S1"], at: date(23, 6, 30)), query: query)
        _ = store.add(trip(["S1"], at: date(23, 6, 30)), query: query)   // doppelt → ignoriert
        #expect(store.trips.count == 1)

        var regular = a
        regular.weekdays = Weekday.workdays
        store.update(regular)
        store.add(trip(["S2"], at: date(23, 7, 0)), query: query)

        let reloaded = SavedTripsStore(defaults: defaults)
        #expect(reloaded.trips.count == 2)
        #expect(reloaded.regular().map(\.id) == [a.id])
        #expect(reloaded.bookmarked.count == 1)

        reloaded.remove(id: a.id)
        #expect(SavedTripsStore(defaults: defaults).trips.count == 1)
    }
}

@Suite struct SavedTripNotificationSettingTests {
    @Test func notificationsDefaultOnAndSurviveEncoding() throws {
        var saved = SavedTrip(trip: trip(["S1"], at: date(23, 6, 30)),
                              query: TripQuery(origin: pirna, destination: postplatz), calendar: berlin)
        #expect(saved.usesNotifications, "neu gemerkte Fahrten melden sich")
        saved.usesNotifications = false
        let decoded = try JSONDecoder().decode(SavedTrip.self, from: JSONEncoder().encode(saved))
        #expect(decoded.usesNotifications == false)

        // Ältere Daten ohne das Feld: eingeschaltet.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        json.removeValue(forKey: "notifications")
        let old = try JSONDecoder().decode(SavedTrip.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.usesNotifications)
    }
}

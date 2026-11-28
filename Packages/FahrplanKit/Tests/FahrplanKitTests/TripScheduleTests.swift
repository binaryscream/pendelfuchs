// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

@Suite struct TripScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private let pirna = Stop(provider: .transitous, stopID: "de-DELFI_de:14628:3370", name: "Pirna Bahnhof")
    private let muenchen = Stop(provider: .transitous, stopID: "de-DELFI_de:09162:6", name: "München Hbf")
    private let unknown = Stop(provider: .transitous, stopID: "flixbus_123", name: "Fernbus")

    private func saved(from origin: Stop, weekdays: Set<Weekday> = Weekday.workdays) -> SavedTrip {
        let json = """
        {"id":"\(UUID().uuidString)","origin":\(encode(origin)),"destination":\(encode(muenchen)),
         "departure":{"hour":7,"minute":36},"lines":["S1"],"modes":[],"weekdays":[],"createdAt":0}
        """
        var trip = try! JSONDecoder().decode(SavedTrip.self, from: Data(json.utf8))
        trip.weekdays = weekdays
        return trip
    }

    private func encode(_ stop: Stop) -> String { String(data: try! JSONEncoder().encode(stop), encoding: .utf8)! }

    @Test func easterDates() {
        func easter(_ year: Int) -> DateComponents {
            var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
            return utc.dateComponents([.month, .day], from: Holidays.easterSunday(year: year)!)
        }
        #expect(easter(2026) == DateComponents(month: 4, day: 5))
        #expect(easter(2027) == DateComponents(month: 3, day: 28))
        #expect(easter(2038) == DateComponents(month: 4, day: 25))
    }

    @Test func nationwideAndMovableHolidays() {
        #expect(Holidays.name(on: day(2027, 1, 1), in: nil, calendar: calendar) == "Neujahr")
        #expect(Holidays.name(on: day(2027, 3, 26), in: nil, calendar: calendar) == "Karfreitag")
        #expect(Holidays.name(on: day(2027, 3, 29), in: nil, calendar: calendar) == "Ostermontag")
        #expect(Holidays.name(on: day(2027, 5, 6), in: nil, calendar: calendar) == "Christi Himmelfahrt")
        #expect(Holidays.name(on: day(2027, 5, 17), in: nil, calendar: calendar) == "Pfingstmontag")
        #expect(Holidays.name(on: day(2027, 3, 30), in: nil, calendar: calendar) == nil)
        // Auch kurz nach Mitternacht und spät abends derselbe Tag (Zeitzone).
        #expect(Holidays.name(on: day(2026, 12, 25, hour: 0), in: nil, calendar: calendar) == "1. Weihnachtstag")
        #expect(Holidays.name(on: day(2026, 12, 26, hour: 23), in: nil, calendar: calendar) == "2. Weihnachtstag")
        #expect(Holidays.name(on: day(2026, 12, 24), in: .sn, calendar: calendar) == nil, "Heiligabend ist kein Feiertag")
    }

    @Test func stateHolidays() {
        // Buß- und Bettag: Mittwoch vor dem 23. November, nur Sachsen.
        #expect(Holidays.name(on: day(2026, 11, 18), in: .sn, calendar: calendar) == "Buß- und Bettag")
        #expect(Holidays.name(on: day(2027, 11, 17), in: .sn, calendar: calendar) == "Buß- und Bettag")
        #expect(Holidays.name(on: day(2026, 11, 18), in: .by, calendar: calendar) == nil)
        #expect(Holidays.name(on: day(2026, 11, 25), in: .sn, calendar: calendar) == nil)
        #expect(Holidays.name(on: day(2026, 10, 31), in: .sn, calendar: calendar) == "Reformationstag")
        #expect(Holidays.name(on: day(2026, 10, 31), in: .by, calendar: calendar) == nil)
        #expect(Holidays.name(on: day(2026, 11, 1), in: .by, calendar: calendar) == "Allerheiligen")
        #expect(Holidays.name(on: day(2027, 5, 27), in: .by, calendar: calendar) == "Fronleichnam")
        #expect(Holidays.name(on: day(2027, 5, 27), in: .sn, calendar: calendar) == nil)
        #expect(Holidays.name(on: day(2027, 1, 6), in: .bw, calendar: calendar) == "Heilige Drei Könige")
        #expect(Holidays.name(on: day(2027, 3, 8), in: .be, calendar: calendar) == "Internationaler Frauentag")
        #expect(Holidays.name(on: day(2026, 10, 31), in: nil, calendar: calendar) == nil, "ohne Land nur bundesweite")
    }

    @Test func stateOfAStop() {
        #expect(FederalState.of(pirna) == .sn)
        #expect(FederalState.of(muenchen) == .by)
        #expect(FederalState.of(unknown) == nil)
        #expect(FederalState.of(Stop(provider: .vvo, stopID: "33003370", name: "Pirna")) == .sn)
        #expect(FederalState(district: "99123") == nil)
    }

    @Test func regularTripSkipsHolidays() throws {
        // Mittwoch, 18.11.2026 ist Buß- und Bettag in Sachsen.
        let tuesdayEvening = day(2026, 11, 17, hour: 20)
        let next = try #require(saved(from: pirna).nextOccurrence(after: tuesdayEvening, calendar: calendar,
                                                                  schedule: TripSchedule()))
        #expect(calendar.component(.day, from: next) == 19, "Mittwoch fällt aus, weiter am Donnerstag")
        let bavaria = try #require(saved(from: muenchen).nextOccurrence(after: tuesdayEvening, calendar: calendar,
                                                                        schedule: TripSchedule()))
        #expect(calendar.component(.day, from: bavaria) == 18, "in Bayern normaler Werktag")
        let off = try #require(saved(from: pirna).nextOccurrence(after: tuesdayEvening, calendar: calendar,
                                                                 schedule: .none))
        #expect(calendar.component(.day, from: off) == 18, "abgeschaltet: fährt auch am Feiertag")
    }

    @Test func chosenStateOverridesTheStop() throws {
        // Wohnen in Sachsen, arbeiten nach bayerischem Kalender (oder umgekehrt): das gewählte Land zählt.
        let tuesdayEvening = day(2026, 11, 17, hour: 20)
        let asBavaria = try #require(saved(from: pirna).nextOccurrence(after: tuesdayEvening, calendar: calendar,
                                                                       schedule: TripSchedule(state: .by)))
        #expect(calendar.component(.day, from: asBavaria) == 18, "Buß- und Bettag gilt in Bayern nicht")
        let asSaxony = try #require(saved(from: muenchen).nextOccurrence(after: tuesdayEvening, calendar: calendar,
                                                                         schedule: TripSchedule(state: .sn)))
        #expect(calendar.component(.day, from: asSaxony) == 19)
        #expect(TripSchedule(state: .by).holidayState(for: unknown) == .by)
        #expect(TripSchedule().holidayState(for: unknown) == nil)
    }

    @Test func listsUpcomingHolidays() {
        let list = Holidays.upcoming(from: day(2026, 11, 28), in: .sn, limit: 4, calendar: calendar)
        #expect(list.map(\.name) == ["1. Weihnachtstag", "2. Weihnachtstag", "Neujahr", "Karfreitag"])
    }

    @Test func pauseSkipsWholeDaysAndResumesAfterwards() throws {
        // Urlaub 21.12.2026 bis 8.1.2027 – dazwischen liegen auch Feiertage.
        let schedule = TripSchedule(pause: day(2026, 12, 21, hour: 0)...day(2027, 1, 8, hour: 0))
        let trip = saved(from: pirna)
        let before = try #require(trip.nextOccurrence(after: day(2026, 12, 18, hour: 6), calendar: calendar,
                                                      schedule: schedule))
        #expect(calendar.dateComponents([.month, .day], from: before) == DateComponents(month: 12, day: 18))
        let during = try #require(trip.nextOccurrence(after: day(2026, 12, 18, hour: 9), calendar: calendar,
                                                      schedule: schedule))
        #expect(calendar.dateComponents([.year, .month, .day], from: during)
                == DateComponents(year: 2027, month: 1, day: 11), "erster Werktag nach dem Urlaub")
        #expect(schedule.skipReason(on: day(2027, 1, 8, hour: 23), origin: pirna, calendar: calendar)
                == .paused(until: day(2027, 1, 8, hour: 0)), "der letzte Tag gehört ganz dazu")
        #expect(schedule.skipReason(on: day(2027, 1, 9), origin: pirna, calendar: calendar) == nil)
        #expect(schedule.activePause(on: day(2027, 1, 8), calendar: calendar) != nil)
        #expect(schedule.activePause(on: day(2027, 1, 9), calendar: calendar) == nil, "abgelaufen")
    }

    @Test func tellsWhyTodayIsSkipped() throws {
        let trip = saved(from: pirna)
        let skipped = try #require(trip.skippedOccurrence(after: day(2026, 11, 18, hour: 6), calendar: calendar,
                                                          schedule: TripSchedule()))
        #expect(skipped.reason == .holiday("Buß- und Bettag"))
        #expect(trip.skippedOccurrence(after: day(2026, 11, 19, hour: 6), calendar: calendar,
                                       schedule: TripSchedule()) == nil)
    }

    @Test func savesAndLoads() throws {
        let name = "schedule-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(TripSchedule.load(from: defaults) == TripSchedule(skipHolidays: true, pause: nil))
        let schedule = TripSchedule(skipHolidays: false, state: .by, pause: day(2026, 12, 21)...day(2027, 1, 8))
        schedule.save(to: defaults)
        #expect(TripSchedule.load(from: defaults) == schedule)
        TripSchedule(skipHolidays: true).save(to: defaults)
        #expect(TripSchedule.load(from: defaults).pause == nil)
        #expect(TripSchedule.load(from: defaults).state == nil, "zurück auf automatisch")
    }
}

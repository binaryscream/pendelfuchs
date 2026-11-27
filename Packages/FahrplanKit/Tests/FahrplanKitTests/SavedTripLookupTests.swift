// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private let berlin: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func date(_ hour: Int, _ minute: Int) -> Date {
    berlin.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour, minute: minute))!
}

private func trip(at dep: Date, id: String?, cancelled: Bool = false) -> Trip {
    var stops = [
        TripStop(stopID: "a", name: "Pirna", place: nil, platform: nil, arrival: nil, departure: TimePoint(scheduledTime: dep)),
        TripStop(stopID: "b", name: "Dresden", place: nil, platform: nil,
                 arrival: TimePoint(scheduledTime: dep.addingTimeInterval(20 * 60)), departure: nil),
    ]
    if cancelled { for i in stops.indices { stops[i].isCancelled = true } }
    let leg = TripLeg(kind: .ride, mode: .suburbanRailway, line: "S1", stops: stops)
    return Trip(legs: [leg], interchanges: 0, source: .transitous, itineraryID: id)
}

/// Zählt Suchen und Abholungen; liefert vorgegebene Antworten.
private final class FakeProvider: TransitProvider, @unchecked Sendable {
    let id: ProviderID = .transitous
    var planResult: [Trip] = []
    var refreshResult: Trip?
    var refreshFails = false
    var plans = 0
    var refreshes = 0

    func searchStops(query: String) async throws -> [Stop] { [] }
    func nearbyStops(around coordinate: Coordinate) async throws -> [Stop] { [] }
    func departures(at stop: Stop, limit: Int, from: Date?) async throws -> [Departure] { [] }
    func journey(of departure: Departure, at stop: Stop) async throws -> TripLeg { throw TransitError.badResponse(status: 0) }
    func trips(_ query: TripQuery) async throws -> [Trip] { plans += 1; return planResult }
    func refresh(itineraryID: String, options: TripOptions) async throws -> Trip? {
        refreshes += 1
        if refreshFails { throw TransitError.badResponse(status: 404) }
        return refreshResult
    }
}

@Suite struct SavedTripLookupTests {
    let query = TripQuery(origin: Stop(provider: .transitous, stopID: "a", name: "Pirna"),
                          destination: Stop(provider: .transitous, stopID: "b", name: "Dresden"))

    private func setup() -> (SavedTrip, String) {
        let suite = "test.\(UUID().uuidString)"
        let saved = SavedTrip(trip: trip(at: date(6, 30), id: "x"), query: query, weekdays: Weekday.workdays, calendar: berlin)
        return (saved, suite)
    }

    @Test func firstLookupSearchesThenOnlyRefreshes() async throws {
        let (saved, suite) = setup()
        let provider = FakeProvider()
        provider.planResult = [trip(at: date(6, 30), id: "abc")]
        provider.refreshResult = trip(at: date(6, 30), id: "abc")

        let first = try await SavedTripLookup.lookup(saved, on: date(12, 0), now: date(6, 0), using: provider,
                                                     suite: suite, calendar: berlin)
        #expect(!first.refreshed && provider.plans == 1 && provider.refreshes == 0)
        #expect(first.match?.itineraryID == "abc")

        let second = try await SavedTripLookup.lookup(saved, on: date(12, 0), now: date(6, 5), using: provider,
                                                      suite: suite, calendar: berlin)
        #expect(second.refreshed && provider.plans == 1 && provider.refreshes == 1)
        #expect(second.resolved?.note == nil)
    }

    @Test func disruptionOrFailureFallsBackToSearch() async throws {
        let (saved, suite) = setup()
        let provider = FakeProvider()
        provider.planResult = [trip(at: date(6, 30), id: "abc"), trip(at: date(6, 45), id: "next")]
        _ = try await SavedTripLookup.lookup(saved, on: date(6, 0), now: date(6, 0), using: provider,
                                             suite: suite, calendar: berlin)

        // Abgeholte Verbindung fällt aus → neu suchen, damit der Verpass-Assistent einen Ersatz findet.
        provider.refreshResult = trip(at: date(6, 30), id: "abc", cancelled: true)
        provider.planResult = [trip(at: date(6, 30), id: "abc", cancelled: true), trip(at: date(6, 45), id: "next")]
        let cancelled = try await SavedTripLookup.lookup(saved, on: date(6, 0), now: date(6, 10), using: provider,
                                                         suite: suite, calendar: berlin)
        #expect(!cancelled.refreshed && provider.plans == 2)
        #expect(cancelled.resolved?.trip.itineraryID == "next")
        #expect(cancelled.resolved?.note != nil)

        // Abholen scheitert (z. B. Schnittstelle geändert) → wie früher suchen.
        provider.refreshFails = true
        provider.planResult = [trip(at: date(6, 30), id: "abc")]
        let failed = try await SavedTripLookup.lookup(saved, on: date(6, 0), now: date(6, 15), using: provider,
                                                      suite: suite, calendar: berlin)
        #expect(!failed.refreshed && provider.plans == 3)
        #expect(failed.match != nil)
    }

    @Test func withoutIDAlwaysSearchesAndOldIDsExpire() async throws {
        let (saved, suite) = setup()
        let provider = FakeProvider()
        provider.planResult = [trip(at: date(6, 30), id: nil)]   // z. B. VVO
        _ = try await SavedTripLookup.lookup(saved, on: date(6, 0), now: date(6, 0), using: provider,
                                             suite: suite, calendar: berlin)
        _ = try await SavedTripLookup.lookup(saved, on: date(6, 0), now: date(6, 5), using: provider,
                                             suite: suite, calendar: berlin)
        #expect(provider.plans == 2 && provider.refreshes == 0)

        let defaults = try #require(UserDefaults(suiteName: suite))
        SavedTripLookup.save(["\(saved.id.uuidString)|\(Int(date(6, 30).timeIntervalSince1970))": "old"], defaults)
        #expect(SavedTripLookup.load(defaults, now: date(6, 0).addingTimeInterval(3 * 24 * 3600)).isEmpty)
    }
}

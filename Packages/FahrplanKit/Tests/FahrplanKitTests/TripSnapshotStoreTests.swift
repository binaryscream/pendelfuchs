// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

@Suite struct TripSnapshotStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_795_800_000)

    private func makeStore() -> TripSnapshotStore {
        TripSnapshotStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshots-\(UUID().uuidString)"))
    }

    private var trip: Trip {
        let stop = TripStop(stopID: "a", name: "A", place: nil, platform: "1", arrival: nil,
                            departure: TimePoint(scheduledTime: t0, realTime: t0 + 120))
        return Trip(legs: [TripLeg(kind: .ride, mode: .tram, line: "7", stops: [stop])], interchanges: 0)
    }

    @Test func savesAndLoadsPerTripAndOccurrence() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let id = UUID()
        #expect(store.load(for: id, occurrence: t0) == nil)
        store.save(trip, note: "Ersatz", for: id, occurrence: t0, now: t0 - 600)
        let snapshot = try #require(store.load(for: id, occurrence: t0))
        #expect(snapshot.trip == trip && snapshot.note == "Ersatz" && snapshot.fetchedAt == t0 - 600)
        #expect(store.load(for: id, occurrence: t0 + 86_400) == nil, "anderer Termin")
        #expect(store.load(for: UUID(), occurrence: t0) == nil, "andere Fahrt")
    }

    @Test func prunesOldOccurrencesAndClears() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let id = UUID()
        store.save(trip, note: nil, for: id, occurrence: t0 - 3 * 86_400)
        store.save(trip, note: nil, for: id, occurrence: t0)
        store.prune(now: t0)
        #expect(store.load(for: id, occurrence: t0 - 3 * 86_400) == nil)
        #expect(store.load(for: id, occurrence: t0) != nil)
        store.removeAll()
        #expect(store.load(for: id, occurrence: t0) == nil)
    }
}

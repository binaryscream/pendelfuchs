// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

@MainActor
@Suite struct RecentsStoreTests {
    private func stop(_ number: Int) -> Stop {
        Stop(provider: .vvo, stopID: "\(number)", name: "Halt \(number)", place: "Dresden", distance: 100)
    }

    private func defaults() throws -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func newestFirstWithoutDuplicates() throws {
        let store = RecentsStore(defaults: try defaults())
        store.use(stop(1)); store.use(stop(2)); store.use(stop(1))
        #expect(store.stops.map(\.stopID) == ["1", "2"])
        #expect(store.stops[0].distance == nil, "Entfernung wird nicht gemerkt")
    }

    @Test func keepsOnlyTheNewest() throws {
        let store = RecentsStore(defaults: try defaults())
        for number in 1...12 { store.use(stop(number)) }
        #expect(store.stops.count == RecentsStore.maxStops)
        #expect(store.stops.first?.stopID == "12")
        for number in 1...8 { store.use(origin: stop(number), destination: stop(number + 20)) }
        #expect(store.routes.count == RecentsStore.maxRoutes)
        #expect(store.routes.first?.origin.stopID == "8")
    }

    @Test func persistsAndRemoves() throws {
        let defaults = try defaults()
        let store = RecentsStore(defaults: defaults)
        store.use(stop(1)); store.use(stop(2))
        store.use(origin: stop(1), destination: stop(2))
        store.remove(stop(2))

        let reloaded = RecentsStore(defaults: defaults)
        #expect(reloaded.stops.map(\.stopID) == ["1"])
        #expect(reloaded.routes.count == 1)
        reloaded.clear()
        #expect(RecentsStore(defaults: defaults).routes.isEmpty)
    }
}

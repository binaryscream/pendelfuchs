// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Eine zuletzt gesuchte Strecke.
public struct RecentRoute: Codable, Sendable, Hashable, Identifiable {
    public var origin: Stop
    public var destination: Stop

    public var id: String { "\(origin.id)>\(destination.id)" }

    public init(origin: Stop, destination: Stop) {
        self.origin = origin
        self.destination = destination
    }
}

/// Zuletzt verwendete Haltestellen und zuletzt gesuchte Strecken – das Neueste zuerst, nur auf dem Gerät.
@MainActor
@Observable
public final class RecentsStore {
    public private(set) var stops: [Stop] = []
    public private(set) var routes: [RecentRoute] = []

    public static let maxStops = 8
    public static let maxRoutes = 5

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let stopsKey = "recentStops.v1"
    @ObservationIgnored private let routesKey = "recentRoutes.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: stopsKey), let saved = try? JSONDecoder().decode([Stop].self, from: data) {
            stops = saved
        }
        if let data = defaults.data(forKey: routesKey),
           let saved = try? JSONDecoder().decode([RecentRoute].self, from: data) {
            routes = saved
        }
    }

    /// Merkt eine Haltestelle als gerade verwendet (rückt an die erste Stelle).
    public func use(_ stop: Stop) {
        let clean = Self.clean(stop)
        guard stops.first?.id != clean.id else { return }
        stops = Array(([clean] + stops.filter { $0.id != clean.id }).prefix(Self.maxStops))
        save()
    }

    /// Merkt eine Strecke als gerade gesucht (rückt an die erste Stelle).
    public func use(origin: Stop, destination: Stop) {
        let route = RecentRoute(origin: Self.clean(origin), destination: Self.clean(destination))
        guard routes.first?.id != route.id else { return }
        routes = Array(([route] + routes.filter { $0.id != route.id }).prefix(Self.maxRoutes))
        save()
    }

    public func remove(_ stop: Stop) {
        stops.removeAll { $0.id == stop.id }
        save()
    }

    public func remove(_ route: RecentRoute) {
        routes.removeAll { $0.id == route.id }
        save()
    }

    public func clear() {
        stops = []
        routes = []
        save()
    }

    /// Die Entfernung gilt nur für den Moment der Umkreissuche.
    private static func clean(_ stop: Stop) -> Stop {
        var clean = stop
        clean.distance = nil
        return clean
    }

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(stops) { defaults.set(data, forKey: stopsKey) }
        if let data = try? encoder.encode(routes) { defaults.set(data, forKey: routesKey) }
    }
}

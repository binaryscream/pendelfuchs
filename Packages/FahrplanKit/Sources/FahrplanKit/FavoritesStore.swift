// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Favoriten-Haltestellen, gespeichert in `UserDefaults`.
/// Später mit einer App-Group-Suite initialisieren, damit Widgets dieselben Daten sehen.
@MainActor
@Observable
public final class FavoritesStore {
    public private(set) var stops: [Stop] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "favoriteStops.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([Stop].self, from: data) {
            stops = saved
        }
    }

    public func contains(_ stop: Stop) -> Bool {
        stops.contains { $0.id == stop.id }
    }

    public func toggle(_ stop: Stop) {
        if contains(stop) { remove(stop) } else { add(stop) }
    }

    public func add(_ stop: Stop) {
        guard !contains(stop) else { return }
        var clean = stop
        clean.distance = nil   // Entfernung ist nur für die Umkreissuche relevant
        stops.append(clean)
        save()
    }

    public func remove(_ stop: Stop) {
        stops.removeAll { $0.id == stop.id }
        save()
    }

    public func remove(atOffsets offsets: IndexSet) {
        stops = stops.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        save()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var copy = stops
        let moving = source.sorted().map { copy[$0] }
        for index in source.sorted(by: >) { copy.remove(at: index) }
        let insertAt = destination - source.filter { $0 < destination }.count
        copy.insert(contentsOf: moving, at: insertAt)
        stops = copy
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stops) {
            defaults.set(data, forKey: key)
        }
    }
}

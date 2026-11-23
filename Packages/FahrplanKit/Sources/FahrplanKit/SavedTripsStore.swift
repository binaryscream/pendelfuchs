// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Gemerkte und regelmäßige Fahrten, gespeichert in `UserDefaults`.
/// Später mit einer App-Group-Suite initialisieren, damit Widgets und Live-Aktivitäten sie sehen.
@MainActor
@Observable
public final class SavedTripsStore {
    public private(set) var trips: [SavedTrip] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "savedTrips.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([SavedTrip].self, from: data) {
            trips = saved
        }
    }

    /// Regelmäßige Fahrten, nach nächstem Termin sortiert.
    public func regular(now: Date = .now) -> [SavedTrip] {
        trips.filter(\.isRegular).sorted {
            ($0.nextOccurrence(after: now) ?? .distantFuture) < ($1.nextOccurrence(after: now) ?? .distantFuture)
        }
    }

    /// Nur gemerkte Fahrten, nach Uhrzeit sortiert.
    public var bookmarked: [SavedTrip] {
        trips.filter { !$0.isRegular }.sorted { $0.departure < $1.departure }
    }

    public func trip(id: UUID) -> SavedTrip? {
        trips.first { $0.id == id }
    }

    public func saved(matching trip: Trip, query: TripQuery) -> SavedTrip? {
        trips.first { $0.isSame(as: trip, query: query) }
    }

    @discardableResult
    public func add(_ trip: Trip, query: TripQuery) -> SavedTrip {
        if let existing = saved(matching: trip, query: query) { return existing }
        let saved = SavedTrip(trip: trip, query: query)
        trips.append(saved)
        save()
        return saved
    }

    public func update(_ trip: SavedTrip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
        save()
    }

    public func remove(id: UUID) {
        trips.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(trips) {
            defaults.set(data, forKey: key)
        }
    }
}

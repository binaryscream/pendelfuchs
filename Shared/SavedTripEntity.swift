// SPDX-License-Identifier: GPL-3.0-or-later
// Gemeinsam genutzt von App (Kurzbefehle, Siri) und Widget-Erweiterung (Auswahl im Widget).

import AppIntents
import FahrplanKit
import Foundation

/// Gemerkte Fahrt als Auswahl in der Kurzbefehle-App und im Widget „Meine nächste Fahrt“.
struct SavedTripEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Gemerkte Fahrt"
    static let defaultQuery = SavedTripEntityQuery()

    let id: UUID
    let title: String
    let subtitle: String

    init(_ saved: SavedTrip) {
        id = saved.id
        title = saved.title(style: .current)
        subtitle = "\(saved.departure.formatted) · \(saved.lines.joined(separator: " › ")) · \(saved.weekdays.summary)"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }
}

struct SavedTripEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SavedTripEntity] {
        let store = SavedTripsStore(defaults: AppGroup.defaults)
        return identifiers.compactMap { store.trip(id: $0) }.map(SavedTripEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SavedTripEntity] {
        let store = SavedTripsStore(defaults: AppGroup.defaults)
        return (store.regular() + store.bookmarked).map(SavedTripEntity.init)
    }
}

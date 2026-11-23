// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import FahrplanKit
import Foundation

/// Gemerkte Fahrt als Auswahl in der Kurzbefehle-App.
struct SavedTripEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Gemerkte Fahrt"
    static let defaultQuery = SavedTripEntityQuery()

    let id: UUID
    let title: String
    let subtitle: String

    init(_ saved: SavedTrip) {
        id = saved.id
        title = saved.title
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

/// „Live-Aktivität starten“ – gedacht für eine Kurzbefehle-Automation (z. B. Mo–Fr 6:15).
/// Ohne gewählte Fahrt wird die nächste regelmäßige Fahrt der kommenden drei Stunden genommen.
struct StartTripActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Live-Aktivität starten"
    static let description = IntentDescription(
        "Zeigt eine gemerkte Fahrt mit Echtzeitdaten auf dem Sperrbildschirm und in der Dynamic Island.")

    @Parameter(title: "Fahrt", description: "Leer lassen für die nächste regelmäßige Fahrt.")
    var trip: SavedTripEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Live-Aktivität für \(\.$trip) starten")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SavedTripsStore(defaults: AppGroup.defaults)
        let saved: SavedTrip
        if let trip {
            guard let found = store.trip(id: trip.id) else {
                return .result(dialog: "Diese Fahrt ist nicht mehr gespeichert.")
            }
            saved = found
        } else {
            let now = Date.now
            guard let next = store.regular(now: now).first(where: {
                ($0.nextOccurrence(after: now) ?? .distantFuture) < now.addingTimeInterval(3 * 3600)
            }) else {
                return .result(dialog: "In den nächsten drei Stunden steht keine regelmäßige Fahrt an.")
            }
            saved = next
        }

        try await TripActivityManager.shared.start(saved)
        return .result(dialog: "Live-Aktivität für „\(saved.title)“ gestartet.")
    }
}

/// Macht die Aktion in Kurzbefehle und Siri ohne Einrichtung verfügbar.
struct FahrplanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTripActivityIntent(),
            phrases: [
                "Live-Aktivität in \(.applicationName) starten",
                "Nächste Fahrt in \(.applicationName)",
            ],
            shortTitle: "Live-Aktivität starten",
            systemImageName: "tram.fill"
        )
    }
}

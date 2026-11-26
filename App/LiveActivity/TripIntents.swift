// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import FahrplanKit
import Foundation

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
        return .result(dialog: "Live-Aktivität für „\(saved.title(style: .current))“ gestartet.")
    }
}

/// Macht die Aktion in Kurzbefehle und Siri ohne Einrichtung verfügbar.
struct FahrplanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTripActivityIntent(),
            phrases: [
                "Live-Aktivität in \(.applicationName) starten",
                "Starte Live-Aktivität mit \(.applicationName)",
                "\(.applicationName) Live-Aktivität starten",
            ],
            shortTitle: "Live-Aktivität starten",
            systemImageName: "tram.fill"
        )
        AppShortcut(
            intent: EndTripActivitiesIntent(),
            phrases: [
                "Live-Aktivität in \(.applicationName) beenden",
                "Beende Live-Aktivität in \(.applicationName)",
                "\(.applicationName) Live-Aktivität beenden",
                "Stoppe Live-Aktivität in \(.applicationName)",
            ],
            shortTitle: "Live-Aktivität beenden",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: TripConnectionIntent(),
            // Je Satz höchstens eine Haltestelle (Vorgabe von iOS) – nach dem Start fragt Siri nach. Nur das Ziel
            // als Platzhalter: Mit Start und Ziel zeigt die Kurzbefehle-App jede Haltestelle doppelt.
            phrases: [
                "Verbindung in \(.applicationName)",
                "Verbindung suchen in \(.applicationName)",
                "Verbindung mit \(.applicationName)",
                "\(.applicationName) Verbindung",
                "Verbindung nach \(\.$destination) in \(.applicationName)",
                "Wie komme ich nach \(\.$destination) mit \(.applicationName)",
                "\(.applicationName) Verbindung nach \(\.$destination)",
            ],
            shortTitle: "Verbindung suchen",
            systemImageName: "point.topleft.down.to.point.bottomright.curvepath"
        )
        AppShortcut(
            intent: NextDeparturesIntent(),
            // Der App-Name steht in jeder Variante – sonst übernimmt Siri den Satz selbst oder eine andere App.
            phrases: [
                "Abfahrten in \(.applicationName)",
                "Abfahrten mit \(.applicationName)",
                "\(.applicationName) Abfahrten",
                "Zeig Abfahrten in \(.applicationName)",
                "Nächste Abfahrten in \(.applicationName)",
                "Nächste Abfahrten an \(\.$stop) in \(.applicationName)",
                "Abfahrten an \(\.$stop) mit \(.applicationName)",
                "\(.applicationName) Abfahrten \(\.$stop)",
                "Was fährt ab \(\.$stop) in \(.applicationName)",
            ],
            shortTitle: "Nächste Abfahrten",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: SavedTripStatusIntent(),
            phrases: [
                "Wie fährt meine Fahrt in \(.applicationName)",
                "Nächste Fahrt in \(.applicationName)",
                "Meine Fahrt mit \(.applicationName)",
                "\(.applicationName) meine Fahrt",
                "Stand von \(\.$trip) in \(.applicationName)",
                "\(.applicationName) \(\.$trip)",
            ],
            shortTitle: "Stand meiner Fahrt",
            systemImageName: "star"
        )
    }
}

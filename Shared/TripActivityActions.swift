// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import Foundation

/// Verbindung zwischen den Knöpfen in der Live-Aktivität (Widget-Erweiterung) und der App:
/// Die Intents laufen im App-Prozess; die App hängt beim Start ihre Funktionen hier ein.
enum TripActivityActions {
    @MainActor static var refresh: (() async -> Void)?
    @MainActor static var end: ((UUID) async -> Void)?
}

/// Knopf „Aktualisieren“ in der Live-Aktivität: holt Echtzeitdaten und schaltet auf die aktuelle Phase.
struct RefreshTripActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Live-Aktivität aktualisieren"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await TripActivityActions.refresh?()
        return .result()
    }
}

/// Knopf „Beenden“ in der Live-Aktivität.
struct EndTripActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Live-Aktivität beenden"
    static let isDiscoverable = false

    @Parameter(title: "Fahrt")
    var tripID: String

    init() {}

    init(id: UUID) {
        tripID = id.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: tripID) { await TripActivityActions.end?(id) }
        return .result()
    }
}

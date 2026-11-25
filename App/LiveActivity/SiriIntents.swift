// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import FahrplanKit
import Foundation

/// „Nächste Abfahrten an …“ – Siri liest die nächsten Abfahrten einer Haltestelle vor.
struct NextDeparturesIntent: AppIntent {
    static let title: LocalizedStringResource = "Nächste Abfahrten"
    static let description = IntentDescription("Nennt die nächsten Abfahrten an einer Haltestelle.")

    @Parameter(title: "Haltestelle", description: "Leer lassen für den ersten Favoriten.")
    var stop: StopEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Nächste Abfahrten an \(\.$stop)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let stop = stop?.stop ?? FavoritesStore(defaults: AppGroup.defaults).stops.first else {
            return .result(dialog: "Wähle eine Haltestelle oder lege in der App einen Favoriten an.")
        }
        let name = stop.label(.current)
        let departures = try await DataSources.router().departures(at: stop, limit: 12)
        let upcoming = departures.prefix(4)
        guard !upcoming.isEmpty else {
            return .result(dialog: "An \(name) fährt in nächster Zeit nichts ab.")
        }
        let now = Date.now
        let parts = upcoming.map { SiriText.departure($0, now: now) }
        return .result(dialog: "\(name): \(parts.joined(separator: ", ")).")
    }
}

/// „Wie fährt meine Fahrt?“ – Stand der nächsten Fahrt einer gemerkten Verbindung.
struct SavedTripStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Stand einer gemerkten Fahrt"
    static let description = IntentDescription(
        "Nennt Abfahrt, Gleis und Verspätung der nächsten Fahrt – oder die Ersatzverbindung bei Ausfall.")

    @Parameter(title: "Fahrt", description: "Leer lassen für die nächste regelmäßige Fahrt.")
    var trip: SavedTripEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Stand von \(\.$trip)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SavedTripsStore(defaults: AppGroup.defaults)
        let now = Date.now
        let saved: SavedTrip
        if let trip {
            guard let found = store.trip(id: trip.id) else {
                return .result(dialog: "Diese Fahrt ist nicht mehr gespeichert.")
            }
            saved = found
        } else {
            guard let next = store.regular(now: now).first else {
                return .result(dialog: "Du hast noch keine regelmäßige Fahrt gemerkt.")
            }
            saved = next
        }

        // Regelmäßig: nächster Termin; nur gemerkt: heute (bzw. morgen, wenn schon vorbei).
        let day = saved.nextOccurrence(after: now) ?? {
            let today = saved.departure.date(on: now) ?? now
            return today > now.addingTimeInterval(-15 * 60) ? today : today.addingTimeInterval(24 * 3600)
        }()
        let title = saved.title(style: .current)
        switch await LiveState.load(saved, on: day, using: DataSources.router()) {
        case .found(let trip):
            return .result(dialog: "\(title): \(SiriText.trip(trip, now: now))")
        case .rerouted(let trip, let note):
            return .result(dialog: "\(title): \(note). \(SiriText.trip(trip, now: now))")
        case .notFound:
            return .result(dialog: "\(title): Die Verbindung wurde zur gewohnten Zeit nicht gefunden.")
        case .failed:
            return .result(dialog: "\(title): Gerade sind keine Fahrplandaten erreichbar.")
        case .idle, .loading:
            return .result(dialog: "\(title): Kein Stand verfügbar.")
        }
    }
}

/// Kurze, gut vorlesbare Sätze.
enum SiriText {
    private static let time = Date.FormatStyle.dateTime.hour().minute()

    /// „3 nach Wilder Mann in 4 Minuten“, „S1 nach Meißen um 18:36, 3 Minuten später“.
    static func departure(_ departure: Departure, now: Date) -> String {
        let head = "\(departure.line) nach \(departure.direction)"
        if departure.state == .cancelled { return "\(head) fällt aus" }
        let expected = departure.realTime ?? departure.scheduledTime
        let minutes = Int((expected.timeIntervalSince(now) / 60).rounded(.down))
        var text = minutes <= 0 ? "\(head) jetzt"
            : minutes < 60 ? "\(head) in \(minutes) \(minutes == 1 ? "Minute" : "Minuten")"
            : "\(head) um \(expected.formatted(time))"
        if let realTime = departure.realTime {
            let delay = Int((realTime.timeIntervalSince(departure.scheduledTime) / 60).rounded())
            if delay >= 2 { text += ", \(delay) Minuten später" }
        }
        return text
    }

    /// „Abfahrt 18:38 mit S1 von Gleis 1, 2 Minuten später. Ankunft 19:10.“
    static func trip(_ trip: Trip, now: Date) -> String {
        if let disruption = trip.disruption { return disruption.rerouteNote + "." }
        let first = trip.rides.first
        var text = "Abfahrt \(trip.departure.expectedTime.formatted(time))"
        if let line = first?.line { text += " mit \(line)" }
        if let stop = first?.stops.first, let platform = stop.platform {
            let label = (first?.mode ?? .other).platformLabel(platform).replacingOccurrences(of: "Gl. ", with: "Gleis ")
            text += " von \(label)"
            if stop.platformChanged { text += " – Gleiswechsel" }
        }
        if let delay = trip.departure.delayMinutes, delay >= 2 { text += ", \(delay) Minuten später" }
        text += ". Ankunft \(trip.arrival.expectedTime.formatted(time))."
        return text
    }
}

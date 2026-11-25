// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import FahrplanKit
import Foundation

/// Haltestelle als Auswahl im Widget-Bearbeiten-Dialog, in Kurzbefehlen und für Siri.
struct StopEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Haltestelle"
    static let defaultQuery = StopEntityQuery()

    /// Enthält die komplette Haltestelle, damit auch gesuchte (nicht favorisierte) Haltestellen funktionieren.
    let id: String
    let stop: Stop

    init?(_ stop: Stop) {
        guard let token = StopToken.encode(stop) else { return nil }
        id = token
        self.stop = stop
    }

    /// Behält die angefragte ID exakt bei (App Intents ordnet Ergebnisse über die ID zu).
    init?(id: String) {
        guard let stop = StopToken.decode(id) else { return nil }
        self.id = id
        self.stop = stop
    }

    var displayRepresentation: DisplayRepresentation {
        let style = StopNameStyle.current
        return DisplayRepresentation(title: "\(stop.label(style))", subtitle: "\(stop.secondaryLine(style) ?? "")")
    }
}

struct StopEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StopEntity] {
        identifiers.compactMap { StopEntity(id: $0) }
    }

    /// Ohne Suchtext: die Favoriten.
    @MainActor
    func suggestedEntities() async throws -> [StopEntity] {
        FavoritesStore(defaults: AppGroup.defaults).stops.compactMap(StopEntity.init)
    }

    /// Mit Suchtext: Treffer der Datenquelle, nach Nähe zu den Favoriten und zum zuletzt bekannten Standort
    /// sortiert. Treffer weit weg davon (ganz Europa) fallen weg, solange es nähere gibt.
    func entities(matching string: String) async throws -> [StopEntity] {
        let found = try await DataSources.router().searchStops(query: string)
        let anchors = await MainActor.run {
            [LastLocation.coordinate].compactMap { $0 }
                + FavoritesStore(defaults: AppGroup.defaults).stops.compactMap(\.coordinate)
        }
        return StopSearchRegion.narrow(found, around: anchors).prefix(20).compactMap(StopEntity.init)
    }
}

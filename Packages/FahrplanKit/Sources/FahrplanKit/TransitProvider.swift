// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Gemeinsame Schnittstelle aller Datenquellen. Neue Verbünde implementieren
/// dieses Protokoll; der (spätere) `ProviderRouter` wählt dann pro Anfrage die beste Quelle.
public protocol TransitProvider: Sendable {
    var id: ProviderID { get }

    /// Haltestellen per Freitext suchen.
    func searchStops(query: String) async throws -> [Stop]

    /// Haltestellen im Umkreis einer Koordinate, nach Entfernung sortiert.
    func nearbyStops(around coordinate: Coordinate) async throws -> [Stop]

    /// Nächste Abfahrten an einer Haltestelle.
    func departures(at stop: Stop, limit: Int) async throws -> [Departure]

    /// Verbindungen von A nach B (optional über einen Zwischenhalt), nach Abfahrt sortiert.
    func trips(_ query: TripQuery) async throws -> [Trip]

    /// Kompletter Fahrtverlauf einer Abfahrt (alle Halte, Echtzeit, Strecke).
    func journey(of departure: Departure, at stop: Stop) async throws -> TripLeg
}

public enum TransitError: LocalizedError, Sendable {
    case badResponse(status: Int)
    case service(message: String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .badResponse(let status): "Der Server antwortete mit Status \(status)."
        case .service(let message): "Der Fahrplandienst meldet: \(message)"
        case .decoding(let detail): "Die Antwort des Servers war unverständlich (\(detail))."
        }
    }
}

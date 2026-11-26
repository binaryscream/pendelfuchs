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

    /// Abfahrten an einer Haltestelle ab `from` (`nil` = jetzt).
    func departures(at stop: Stop, limit: Int, from: Date?) async throws -> [Departure]

    /// Verbindungen von A nach B (optional über einen Zwischenhalt), nach Abfahrt sortiert.
    func trips(_ query: TripQuery) async throws -> [Trip]

    /// Kompletter Fahrtverlauf einer Abfahrt (alle Halte, Echtzeit, Strecke).
    func journey(of departure: Departure, at stop: Stop) async throws -> TripLeg
}

extension TransitProvider {
    /// Nächste Abfahrten an einer Haltestelle.
    public func departures(at stop: Stop, limit: Int) async throws -> [Departure] {
        try await departures(at: stop, limit: limit, from: nil)
    }
}

public enum TransitError: LocalizedError, Sendable {
    case badResponse(status: Int)
    case service(message: String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .badResponse(let status) where status == 429:
            "Der Fahrplandienst bekommt gerade zu viele Anfragen. Bitte in einer Minute noch einmal versuchen."
        case .badResponse(let status): "Der Server antwortete mit Status \(status)."
        case .service(let message): "Der Fahrplandienst meldet: \(message)"
        case .decoding(let detail): "Die Antwort des Servers war unverständlich (\(detail))."
        }
    }
}

extension TransitProvider {
    /// Der komplette Lauf des Fahrzeugs (Endhalt bis Endhalt) für eine Verbindung mit genau einer Fahrt –
    /// also auch die Halte vor dem Einstieg und nach dem Ausstieg. `nil`, wenn die Quelle ihn nicht liefert.
    /// Findet die Fahrt über die Abfahrtstafel am Einstieg, weil Verbindungsabfragen keine Fahrt-Kennung enthalten.
    public func fullRun(of trip: Trip) async -> TripLeg? {
        guard trip.rides.count == 1, let ride = trip.rides.first else { return nil }
        return await fullRun(of: ride, source: trip.source)
    }

    /// Der komplette Lauf des Fahrzeugs für eine einzelne Fahrt einer Verbindung (siehe `fullRun(of:)`).
    public func fullRun(of ride: TripLeg, source: ProviderID?) async -> TripLeg? {
        guard ride.kind == .ride, let board = ride.stops.first,
              let scheduled = ride.departure?.scheduledTime, !ride.isUnusable else { return nil }
        let stop = Stop(provider: source ?? .transitous, stopID: board.stopID, name: board.name, place: board.place)
        do {
            let departures = try await departures(at: stop, limit: 12, from: scheduled > .now ? scheduled : nil)
            guard let match = departures.first(where: {
                $0.line == ride.line && abs($0.scheduledTime.timeIntervalSince(scheduled)) < 60
            }) else { return nil }
            var leg = try await journey(of: match, at: stop)
            if leg.line == nil { leg.line = ride.line }
            // Plausibilität: der Lauf muss unsere Fahrt enthalten.
            // (Kennungen der Halte können aus einer anderen Quelle stammen, deshalb über die Zeiten prüfen.)
            guard let start = leg.departure?.scheduledTime, let end = leg.arrival?.scheduledTime,
                  let rideEnd = ride.arrival?.scheduledTime,
                  start <= scheduled.addingTimeInterval(60), end >= rideEnd.addingTimeInterval(-60) else { return nil }
            return leg
        } catch {
            return nil
        }
    }
}

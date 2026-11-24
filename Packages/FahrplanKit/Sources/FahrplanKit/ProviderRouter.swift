// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Wählt für jede Anfrage die passende Datenquelle („intelligente Quellenwahl“).
///
/// - Standard überall: **Transitous** (ganz Deutschland, inkl. Fernverkehr).
/// - Im VVO-Gebiet zusätzlich **VVO** (Preise, Auslastung) – nur wenn aktiviert (`vvo != nil`).
///   Fällt VVO aus, wird automatisch Transitous verwendet.
/// - Zuordnung über die bundesweite Haltestellen-ID (DHID): `de:14628:3370` ↔ VVO `33003370`.
public struct ProviderRouter: TransitProvider {
    public let id: ProviderID = .transitous

    public let transitous: TransitousProvider
    /// `nil`, wenn VVO-Daten nicht genutzt werden sollen.
    public let vvo: VVOProvider?

    public init(transitous: TransitousProvider = TransitousProvider(), vvo: VVOProvider? = VVOProvider()) {
        self.transitous = transitous
        self.vvo = vvo
    }

    // MARK: Zuordnung

    /// Landkreise im VVO-Gebiet: Dresden, Bautzen, Meißen, Sächsische Schweiz-Osterzgebirge.
    static let vvoDistricts: Set<String> = ["14612", "14625", "14627", "14628"]

    /// `de-DELFI_de:14628:3370:0:1` → `33003370`, sofern die Haltestelle im VVO-Gebiet liegt.
    public static func vvoStopID(fromTransitousID id: String) -> String? {
        let prefix = "de-DELFI_"
        guard id.hasPrefix(prefix) else { return nil }
        let parts = id.dropFirst(prefix.count).split(separator: ":")
        guard parts.count >= 3, parts[0] == "de", vvoDistricts.contains(String(parts[1])),
              let number = Int(parts[2]), number > 0, number < 1_000_000
        else { return nil }
        return "33" + String(format: "%06d", number)
    }

    /// Dieselbe Haltestelle als VVO-Haltestelle, falls möglich.
    func asVVOStop(_ stop: Stop) -> Stop? {
        switch stop.provider {
        case .vvo:
            return stop
        case .transitous:
            guard let id = Self.vvoStopID(fromTransitousID: stop.stopID) else { return nil }
            return Stop(provider: .vvo, stopID: id, name: stop.name, place: stop.place, coordinate: stop.coordinate)
        case .db:
            return nil
        }
    }

    /// Dieselbe Haltestelle als Transitous-Haltestelle (VVO-Haltestellen werden per Suche aufgelöst).
    func asTransitousStop(_ stop: Stop) async throws -> Stop {
        if stop.provider == .transitous { return stop }
        let query = [stop.place, stop.name].compactMap { $0 }.joined(separator: " ")
        guard let match = try await transitous.searchStops(query: query).first else {
            throw TransitError.service(message: "Die Haltestelle „\(stop.displayName)“ wurde nicht gefunden.")
        }
        return match
    }

    // MARK: TransitProvider

    public func searchStops(query: String) async throws -> [Stop] {
        do {
            return try await transitous.searchStops(query: query)
        } catch {
            // Ausfallsicherung: Transitous nicht erreichbar → VVO (nur VVO-Gebiet).
            guard let vvo, !(error is CancellationError) else { throw error }
            return try await vvo.searchStops(query: query)
        }
    }

    public func nearbyStops(around coordinate: Coordinate) async throws -> [Stop] {
        do {
            return try await transitous.nearbyStops(around: coordinate)
        } catch {
            guard let vvo, !(error is CancellationError) else { throw error }
            return try await vvo.nearbyStops(around: coordinate)
        }
    }

    public func departures(at stop: Stop, limit: Int, from: Date?) async throws -> [Departure] {
        // VVO kennt keine Abfahrten in der Vergangenheit – dafür Transitous.
        let isPast = from.map { $0 < Date.now.addingTimeInterval(-60) } ?? false
        if let vvo, !isPast, let vvoStop = asVVOStop(stop) {
            do {
                return try await vvo.departures(at: vvoStop, limit: limit, from: from)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // weiter mit Transitous
            }
        }
        return try await transitous.departures(at: asTransitousStop(stop), limit: limit, from: from)
    }

    public func trips(_ query: TripQuery) async throws -> [Trip] {
        // Komplett im VVO-Gebiet → VVO (liefert zusätzlich Preise).
        if let vvo, let origin = asVVOStop(query.origin), let destination = asVVOStop(query.destination) {
            // Ein Zwischenhalt außerhalb des VVO-Gebiets → gleich Transitous.
            let vvoVia = query.via.flatMap(asVVOStop)
            if query.via == nil || vvoVia != nil {
                var vvoQuery = query
                vvoQuery.origin = origin
                vvoQuery.destination = destination
                vvoQuery.via = vvoVia
                do {
                    let trips = try await vvo.trips(vvoQuery)
                    if !trips.isEmpty { return trips }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // weiter mit Transitous
                }
            }
        }

        var transitousQuery = query
        transitousQuery.origin = try await asTransitousStop(query.origin)
        transitousQuery.destination = try await asTransitousStop(query.destination)
        if let via = query.via { transitousQuery.via = try await asTransitousStop(via) }
        return try await transitous.trips(transitousQuery)
    }

    public func journey(of departure: Departure, at stop: Stop) async throws -> TripLeg {
        switch departure.source {
        case .vvo:
            guard let vvo, let vvoStop = asVVOStop(stop) else {
                throw TransitError.service(message: "VVO-Daten sind ausgeschaltet.")
            }
            return try await vvo.journey(of: departure, at: vvoStop)
        default:
            return try await transitous.journey(of: departure, at: asTransitousStop(stop))
        }
    }
}

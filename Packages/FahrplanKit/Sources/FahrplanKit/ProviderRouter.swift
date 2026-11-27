// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Wählt für jede Anfrage die passende Datenquelle („intelligente Quellenwahl“).
///
/// - Standard überall: **Transitous** (ganz Deutschland, inkl. Fernverkehr).
/// - Im VVO-Gebiet zusätzlich **VVO** (Preise, Auslastung) – nur wenn aktiviert (`vvo != nil`).
///   Fällt VVO aus, wird automatisch Transitous verwendet.
/// - In Sachsen (außerhalb des VVO), Bayern, Baden-Württemberg, NRW und Mecklenburg-Vorpommern die
///   **regionalen Verbünde über TripKit** (`RegionalProvider`) – nur wenn aktiviert (`useRegional`).
///   Fällt der Verbund aus oder findet nichts, wird Transitous verwendet.
/// - Zuordnung über die bundesweite Haltestellen-ID (DHID): `de:14628:3370` ↔ VVO `33003370`, Kreis → Verbund.
public struct ProviderRouter: TransitProvider {
    public let id: ProviderID = .transitous

    public let transitous: TransitousProvider
    /// `nil`, wenn VVO-Daten nicht genutzt werden sollen.
    public let vvo: VVOProvider?
    /// Ob regionale Verbünde über TripKit genutzt werden.
    public let useRegional: Bool

    public init(transitous: TransitousProvider = TransitousProvider(), vvo: VVOProvider? = VVOProvider(),
                useRegional: Bool = true) {
        self.transitous = transitous
        self.vvo = vvo
        self.useRegional = useRegional
    }

    // MARK: Zuordnung

    /// Landkreise im VVO-Gebiet: Dresden, Bautzen, Meißen, Sächsische Schweiz-Osterzgebirge.
    static let vvoDistricts: Set<String> = ["14612", "14625", "14627", "14628"]

    /// `de-DELFI_de:14628:3370:0:1` → `33003370`, sofern die Haltestelle im VVO-Gebiet liegt.
    /// Transitous setzt je nach Datensatz verschiedene Präfixe vor die DHID (`de-DELFI_`,
    /// `at-Railway-Current-Reference-Data-2026_` …) – entscheidend ist nur der `de:Kreis:Nummer`-Teil.
    public static func vvoStopID(fromTransitousID id: String) -> String? {
        guard let dhid = DHID(transitousID: id), vvoDistricts.contains(dhid.district),
              let number = Int(dhid.number), number > 0, number < 1_000_000 else { return nil }
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
        case .db, .vms, .vvv, .bayern, .nvbw, .nrw, .vmv:
            return nil
        }
    }

    /// Regionaler Verbund für eine Haltestelle, sofern regionale Daten eingeschaltet sind.
    func regional(for stop: Stop) -> RegionalProvider? {
        guard useRegional, let network = RegionalNetwork.for(stop) else { return nil }
        return RegionalProvider(network: network)
    }

    /// Dieselbe Haltestelle als Transitous-Haltestelle (VVO-Haltestellen werden per Suche aufgelöst).
    func asTransitousStop(_ stop: Stop) async throws -> Stop {
        if stop.provider == .transitous { return stop }
        let query = [stop.place, stop.name].compactMap { $0 }.joined(separator: " ")
        let found = try await transitous.searchStops(query: query)
        // Nicht blind den ersten Namenstreffer nehmen: Mit bekannter Lage zählt der nächstgelegene Treffer
        // (höchstens 500 m entfernt) – sonst landet man leicht bei einer ähnlich benannten Haltestelle.
        if let here = stop.coordinate {
            let near = found.compactMap { candidate in candidate.coordinate.map { (candidate, Geo.meters(here, $0)) } }
                .filter { $0.1 <= 500 }
                .min { $0.1 < $1.1 }
            if let near { return near.0 }
        }
        guard let match = found.first else {
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
            guard let vvo, !(error is CancellationError), !Task.isCancelled else { throw error }
            return try await vvo.searchStops(query: query)
        }
    }

    public func nearbyStops(around coordinate: Coordinate) async throws -> [Stop] {
        do {
            return try await transitous.nearbyStops(around: coordinate)
        } catch {
            guard let vvo, !(error is CancellationError), !Task.isCancelled else { throw error }
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
        if let regional = regional(for: stop) {
            do {
                let found = try await regional.departures(at: stop, limit: limit, from: from)
                if !found.isEmpty { return found }
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

        // Start und Ziel (und Zwischenhalt) im selben regionalen Verbund → dessen Auskunft.
        if let regional = regional(for: query.origin), RegionalNetwork.for(query.destination) == regional.network,
           query.via.map({ RegionalNetwork.for($0) == regional.network }) ?? true {
            do {
                let trips = try await regional.trips(query)
                if !trips.isEmpty { return trips }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // weiter mit Transitous
            }
        }

        var transitousQuery = query
        transitousQuery.origin = try await asTransitousStop(query.origin)
        transitousQuery.destination = try await asTransitousStop(query.destination)
        if let via = query.via { transitousQuery.via = try await asTransitousStop(via) }
        return try await transitous.trips(transitousQuery)
    }

    /// Kennungen stammen nur von Transitous.
    public func refresh(itineraryID: String, options: TripOptions) async throws -> Trip? {
        try await transitous.refresh(itineraryID: itineraryID, options: options)
    }

    public func journey(of departure: Departure, at stop: Stop) async throws -> TripLeg {
        switch departure.source {
        case .vvo:
            guard let vvo, let vvoStop = asVVOStop(stop) else {
                throw TransitError.service(message: "VVO-Daten sind ausgeschaltet.")
            }
            return try await vvo.journey(of: departure, at: vvoStop)
        case .some(let source) where source.regionalNetwork != nil:
            return try await RegionalProvider(network: source.regionalNetwork!).journey(of: departure, at: stop)
        default:
            return try await transitous.journey(of: departure, at: asTransitousStop(stop))
        }
    }
}

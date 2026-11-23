// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Suchanfrage für Verbindungen.
public struct TripQuery: Codable, Sendable, Hashable {
    public var origin: Stop
    public var destination: Stop
    public var via: Stop?
    public var time: Date
    /// `true`: `time` ist die gewünschte Ankunft, sonst die Abfahrt.
    public var isArrivalTime: Bool
    public var options: TripOptions

    public init(origin: Stop, destination: Stop, via: Stop? = nil, time: Date = .now, isArrivalTime: Bool = false,
                options: TripOptions = .standard) {
        self.origin = origin
        self.destination = destination
        self.via = via
        self.time = time
        self.isArrivalTime = isArrivalTime
        self.options = options
    }
}

/// Eine Verbindung von A nach B, bestehend aus Fahrten und Fußwegen.
public struct Trip: Codable, Sendable, Hashable, Identifiable {
    public var legs: [TripLeg]
    public var interchanges: Int
    /// Fahrpreis (Einzelfahrt) laut Datenquelle, z. B. „6,30 €“.
    public var price: String?
    /// Tarifzonen, z. B. „TZ Pirna (70), TZ Dresden (10)“.
    public var fareZones: String?
    /// Datenquelle (für die Quellenangabe).
    public var source: ProviderID?

    public init(legs: [TripLeg], interchanges: Int, price: String? = nil, fareZones: String? = nil,
                source: ProviderID? = nil) {
        self.legs = legs
        self.interchanges = interchanges
        self.price = price
        self.fareZones = fareZones
        self.source = source
    }

    /// Stabil über mehrere Suchen hinweg (für „Früher/Später“-Zusammenführung).
    public var id: String {
        rides.map { "\($0.line ?? "?")@\(Int($0.departure?.scheduledTime.timeIntervalSince1970 ?? 0))" }
            .joined(separator: "|")
    }

    public var rides: [TripLeg] { legs.filter { $0.kind == .ride } }

    /// Erster Halt mit Abfahrtszeit.
    public var departure: TimePoint { rides.first?.departure ?? legs.first?.departure ?? .init(scheduledTime: .distantPast) }
    /// Letzter Halt mit Ankunftszeit.
    public var arrival: TimePoint { rides.last?.arrival ?? legs.last?.arrival ?? .init(scheduledTime: .distantPast) }

    public var duration: TimeInterval { arrival.expectedTime.timeIntervalSince(departure.expectedTime) }

    public var isCancelled: Bool { rides.contains { $0.isCancelled } }
}

/// Geplante Zeit plus optionale Echtzeit-Prognose.
public struct TimePoint: Codable, Sendable, Hashable {
    public var scheduledTime: Date
    public var realTime: Date?

    public init(scheduledTime: Date, realTime: Date? = nil) {
        self.scheduledTime = scheduledTime
        self.realTime = realTime
    }

    public var expectedTime: Date { realTime ?? scheduledTime }

    public var delayMinutes: Int? {
        guard let realTime else { return nil }
        return Int((realTime.timeIntervalSince(scheduledTime) / 60).rounded())
    }
}

public struct TripLeg: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case ride, walk }

    public var kind: Kind
    public var mode: TransportMode?
    public var line: String?
    public var direction: String?
    public var operatorName: String?
    /// Alle Halte inkl. Ein- und Ausstieg (bei Fußwegen leer).
    public var stops: [TripStop]
    public var durationMinutes: Int?
    public var notes: [String]
    /// Streckenverlauf für die Karte (leer, wenn die Quelle keinen liefert).
    public var path: [Coordinate]

    public init(kind: Kind, mode: TransportMode? = nil, line: String? = nil, direction: String? = nil,
                operatorName: String? = nil, stops: [TripStop] = [], durationMinutes: Int? = nil, notes: [String] = [],
                path: [Coordinate] = []) {
        self.kind = kind
        self.mode = mode
        self.line = line
        self.direction = direction
        self.operatorName = operatorName
        self.stops = stops
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.path = path
    }

    /// Streckenverlauf, notfalls die Luftlinie über die Halte.
    public var drawablePath: [Coordinate] {
        path.count >= 2 ? path : stops.compactMap(\.coordinate)
    }

    public var departure: TimePoint? { stops.first?.departure ?? stops.first?.arrival }
    public var arrival: TimePoint? { stops.last?.arrival ?? stops.last?.departure }
    public var intermediateStops: ArraySlice<TripStop> { stops.count > 2 ? stops.dropFirst().dropLast() : [] }
    public var isCancelled: Bool { stops.contains { $0.isCancelled } }
}

public struct TripStop: Codable, Sendable, Hashable {
    public var stopID: String
    public var name: String
    public var place: String?
    public var platform: String?
    public var arrival: TimePoint?
    public var departure: TimePoint?
    public var isCancelled: Bool
    public var coordinate: Coordinate?

    public init(stopID: String, name: String, place: String?, platform: String?,
                arrival: TimePoint?, departure: TimePoint?, isCancelled: Bool = false, coordinate: Coordinate? = nil) {
        self.stopID = stopID
        self.name = name
        self.place = place
        self.platform = platform
        self.arrival = arrival
        self.departure = departure
        self.isCancelled = isCancelled
        self.coordinate = coordinate
    }

    /// Zeitpunkt, an dem das Fahrzeug den Halt verlässt (bzw. erreicht, beim letzten Halt).
    public var passTime: Date? { (departure ?? arrival)?.expectedTime }
}

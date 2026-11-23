// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Kennung einer Datenquelle (VVO/DVB, DB, …).
public enum ProviderID: String, Codable, Sendable, Hashable, CaseIterable {
    case vvo
    case db
    case transitous

    /// Name für die Quellenangabe in der App.
    public var displayName: String {
        switch self {
        case .vvo: "VVO"
        case .db: "Deutsche Bahn"
        case .transitous: "Transitous"
        }
    }
}

/// WGS84-Koordinate (unabhängig von CoreLocation, damit auch Widgets/Tests sie nutzen können).
public struct Coordinate: Codable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Eine Haltestelle bei einer bestimmten Datenquelle.
public struct Stop: Codable, Sendable, Hashable, Identifiable {
    public var provider: ProviderID
    public var stopID: String
    public var name: String
    public var place: String?
    public var coordinate: Coordinate?
    /// Entfernung in Metern (nur bei Umkreissuche gesetzt).
    public var distance: Int?

    public var id: String { "\(provider.rawValue):\(stopID)" }

    /// „Pirna, Bahnhof“ bzw. nur „Bahnhof“, wenn kein Ort bekannt ist.
    public var displayName: String {
        guard let place, !place.isEmpty else { return name }
        return "\(place), \(name)"
    }

    public init(provider: ProviderID, stopID: String, name: String, place: String? = nil,
                coordinate: Coordinate? = nil, distance: Int? = nil) {
        self.provider = provider
        self.stopID = stopID
        self.name = name
        self.place = place
        self.coordinate = coordinate
        self.distance = distance
    }
}

public enum TransportMode: String, Codable, Sendable, Hashable {
    case tram
    case cityBus
    case regionalBus
    case suburbanRailway   // S-Bahn
    case subway            // U-Bahn
    case train             // Regionalzug (RE/RB)
    case longDistance      // Fernzug (ICE/IC/EC/NJ …)
    case coach             // Fernbus
    case cableway
    case ferry
    case onDemand          // Rufbus, Anrufsammeltaxi
    case other

    public var displayName: String {
        switch self {
        case .tram: "Straßenbahn"
        case .cityBus: "Stadtbus"
        case .regionalBus: "Regionalbus"
        case .suburbanRailway: "S-Bahn"
        case .subway: "U-Bahn"
        case .train: "Regionalzug"
        case .longDistance: "Fernzug"
        case .coach: "Fernbus"
        case .cableway: "Seilbahn"
        case .ferry: "Fähre"
        case .onDemand: "Rufbus"
        case .other: "Sonstiges"
        }
    }
}

public enum DepartureState: String, Codable, Sendable, Hashable {
    case onTime
    case delayed
    case cancelled
    case unknown
}

public enum Occupancy: String, Codable, Sendable, Hashable {
    case manySeats
    case fewSeats
    case standingOnly
    case full
    case unknown
}

public struct Departure: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var line: String
    public var direction: String
    public var platform: String?
    public var mode: TransportMode
    public var scheduledTime: Date
    /// Echtzeit-Prognose; `nil`, wenn keine Echtzeitdaten vorliegen.
    public var realTime: Date?
    public var state: DepartureState
    public var occupancy: Occupancy
    /// Datenquelle (für die Quellenangabe).
    public var source: ProviderID?
    /// Kennung der Fahrt bei der Quelle – für den Fahrtverlauf.
    public var tripID: String?

    public init(id: String, line: String, direction: String, platform: String?, mode: TransportMode,
                scheduledTime: Date, realTime: Date?, state: DepartureState, occupancy: Occupancy,
                source: ProviderID? = nil, tripID: String? = nil) {
        self.id = id
        self.line = line
        self.direction = direction
        self.platform = platform
        self.mode = mode
        self.scheduledTime = scheduledTime
        self.realTime = realTime
        self.state = state
        self.occupancy = occupancy
        self.source = source
        self.tripID = tripID
    }

    /// Voraussichtliche Abfahrt (Echtzeit, sonst Plan).
    public var expectedTime: Date { realTime ?? scheduledTime }

    public var hasRealTime: Bool { realTime != nil }

    /// Verspätung in ganzen Minuten (negativ = zu früh); `nil` ohne Echtzeit.
    public var delayMinutes: Int? {
        guard let realTime else { return nil }
        return Int((realTime.timeIntervalSince(scheduledTime) / 60).rounded())
    }

    /// Minuten bis zur Abfahrt, abgerundet und nie negativ.
    public func minutesUntilDeparture(from now: Date = .now) -> Int {
        max(0, Int(expectedTime.timeIntervalSince(now) / 60))
    }
}


extension TransportMode {
    /// Mit dem Deutschlandticket nutzbar (Nahverkehr). Fernzüge und Fernbusse nicht.
    public var isDeutschlandTicketValid: Bool {
        switch self {
        case .longDistance, .coach: false
        default: true
        }
    }

    /// Fernverkehr anhand der Linienbezeichnung erkennen („ICE 1650“, „IC 2048“, „EC 177“, „NJ 457“, „FLX 1234“).
    public static func isLongDistanceName(_ line: String) -> Bool {
        let prefix = line.uppercased().prefix { $0.isLetter }
        return ["ICE", "IC", "EC", "EN", "NJ", "RJ", "RJX", "ECE", "TGV", "FLX", "ES", "WB"].contains(String(prefix))
    }
}

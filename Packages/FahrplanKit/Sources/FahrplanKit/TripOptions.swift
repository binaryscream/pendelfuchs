// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Verkehrsmittel, wie man sie in den Sucheinstellungen an- und abwählt.
public enum ModeGroup: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case regionalRail   // S-Bahn, RE, RB
    case longDistance   // ICE, IC, EC, Nachtzug
    case subway
    case tram
    case bus
    case coach          // Fernbus
    case ferry
    case cableway
    case onDemand

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .regionalRail: "S-Bahn & Regionalzug"
        case .longDistance: "Fernzug (ICE, IC, EC)"
        case .subway: "U-Bahn"
        case .tram: "Straßenbahn"
        case .bus: "Bus"
        case .coach: "Fernbus"
        case .ferry: "Fähre"
        case .cableway: "Seil- & Bergbahn"
        case .onDemand: "Rufbus & Anrufsammeltaxi"
        }
    }

    public var isDeutschlandTicketValid: Bool { self != .longDistance && self != .coach }

    public init(_ mode: TransportMode) {
        switch mode {
        case .suburbanRailway, .train, .other: self = .regionalRail
        case .longDistance: self = .longDistance
        case .subway: self = .subway
        case .tram: self = .tram
        case .cityBus, .regionalBus: self = .bus
        case .coach: self = .coach
        case .ferry: self = .ferry
        case .cableway: self = .cableway
        case .onDemand: self = .onDemand
        }
    }
}

/// Gehgeschwindigkeit für Fußwege und Umstiege.
public enum WalkingSpeed: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case slow, normal, fast

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .slow: "Langsam"
        case .normal: "Normal"
        case .fast: "Schnell"
        }
    }

    /// Meter pro Sekunde (Transitous).
    var metersPerSecond: Double {
        switch self {
        case .slow: 0.9
        case .normal: 1.2
        case .fast: 1.6
        }
    }

    /// Wert der VVO-API (`standardSettings.walkingSpeed`).
    var vvoValue: String {
        switch self {
        case .slow: "Slow"
        case .normal: "Normal"
        case .fast: "Fast"
        }
    }
}

/// Einstellungen für die Verbindungssuche.
public struct TripOptions: Codable, Sendable, Hashable {
    /// Nur Verbindungen, die mit dem Deutschlandticket gefahren werden dürfen (kein Fernverkehr, kein Fernbus).
    public var deutschlandTicketOnly: Bool
    /// Höchstens so viele Umstiege; `nil` = beliebig.
    public var maxTransfers: Int?
    public var walkingSpeed: WalkingSpeed
    /// Abgewählte Verkehrsmittel.
    public var excludedModes: Set<ModeGroup>

    public init(deutschlandTicketOnly: Bool = false, maxTransfers: Int? = nil,
                walkingSpeed: WalkingSpeed = .normal, excludedModes: Set<ModeGroup> = []) {
        self.deutschlandTicketOnly = deutschlandTicketOnly
        self.maxTransfers = maxTransfers
        self.walkingSpeed = walkingSpeed
        self.excludedModes = excludedModes
    }

    public static let standard = TripOptions()

    public var isStandard: Bool { self == .standard }

    /// Tatsächlich erlaubte Verkehrsmittel (abgewählte und – bei Deutschlandticket – Fernverkehr fallen weg).
    public var allowedModes: Set<ModeGroup> {
        Set(ModeGroup.allCases.filter { !excludedModes.contains($0) && (!deutschlandTicketOnly || $0.isDeutschlandTicketValid) })
    }

    public func allows(_ mode: TransportMode) -> Bool { allowedModes.contains(ModeGroup(mode)) }

    /// Prüft eine gefundene Verbindung (die Quellen halten sich nicht immer an jede Vorgabe).
    public func allows(_ trip: Trip) -> Bool {
        if let maxTransfers, trip.interchanges > maxTransfers { return false }
        return trip.rides.allSatisfy { allows($0.mode ?? .other) }
    }

    /// Kurzbeschreibung für die Suchmaske, z. B. „Deutschlandticket · max. 1 Umstieg · ohne Bus“.
    public var summary: String {
        var parts: [String] = []
        if deutschlandTicketOnly { parts.append("Deutschlandticket") }
        if let maxTransfers {
            parts.append(maxTransfers == 0 ? "ohne Umstieg" : "max. \(maxTransfers) Umstieg\(maxTransfers == 1 ? "" : "e")")
        }
        if walkingSpeed != .normal { parts.append("\(walkingSpeed.displayName) gehen") }
        let excluded = excludedModes.filter { !deutschlandTicketOnly || $0.isDeutschlandTicketValid }
        if !excluded.isEmpty {
            parts.append("ohne " + ModeGroup.allCases.filter(excluded.contains).map(\.displayName).joined(separator: ", "))
        }
        return parts.isEmpty ? "Alle Verkehrsmittel" : parts.joined(separator: " · ")
    }
}

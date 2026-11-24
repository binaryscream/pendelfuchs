// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Inhalt einer Live-Aktivität für eine Fahrt. Bewusst kompakt (ActivityKit erlaubt max. 4 KB)
/// und ohne ActivityKit-Abhängigkeit, damit es testbar bleibt.
public struct TripActivityState: Codable, Hashable, Sendable {
    public struct Ride: Codable, Hashable, Sendable {
        public var line: String
        public var mode: TransportMode
        public var direction: String?
        public var fromName: String
        public var fromPlace: String?
        public var fromPlatform: String?
        public var toName: String
        public var toPlace: String?
        public var toPlatform: String?
        public var departure: TimePoint
        public var arrival: TimePoint
        public var isCancelled: Bool

        public func fromLabel(_ style: StopNameStyle) -> String {
            StopNameStyle.label(name: fromName, place: fromPlace, style: style)
        }

        public func toLabel(_ style: StopNameStyle) -> String {
            StopNameStyle.label(name: toName, place: toPlace, style: style)
        }
    }

    /// Was gerade dran ist – wird beim Anzeigen aus der aktuellen Uhrzeit berechnet.
    public enum Phase: Equatable, Sendable {
        /// Vor der ersten Abfahrt.
        case waiting
        /// Unterwegs in Fahrt `index`.
        case riding(index: Int)
        /// Umstieg, als Nächstes kommt Fahrt `index`.
        case transfer(index: Int)
        case arrived
    }

    public var rides: [Ride]
    public var updatedAt: Date
    /// Hinweis, wenn die gemerkte Fahrt ersetzt wurde (z. B. „Anschluss S2 verpasst – nächste Verbindung“).
    public var note: String?

    public init(rides: [Ride], updatedAt: Date = .now, note: String? = nil) {
        self.rides = rides
        self.updatedAt = updatedAt
        self.note = note
    }

    public init(trip: Trip, updatedAt: Date = .now, note: String? = nil) {
        let rides: [Ride] = trip.rides.prefix(5).compactMap { leg in
            guard let first = leg.stops.first, let last = leg.stops.last,
                  let dep = leg.departure, let arr = leg.arrival else { return nil }
            return Ride(line: leg.line ?? "?", mode: leg.mode ?? .other, direction: leg.direction,
                        fromName: first.name, fromPlace: first.place, fromPlatform: first.platform,
                        toName: last.name, toPlace: last.place, toPlatform: last.platform,
                        departure: dep, arrival: arr, isCancelled: leg.isCancelled)
        }
        self.init(rides: rides, updatedAt: updatedAt, note: note)
    }

    public var departure: TimePoint { rides.first?.departure ?? TimePoint(scheduledTime: updatedAt) }
    public var arrival: TimePoint { rides.last?.arrival ?? TimePoint(scheduledTime: updatedAt) }
    public var isCancelled: Bool { rides.contains(where: \.isCancelled) }

    public func phase(at now: Date) -> Phase {
        guard !rides.isEmpty else { return .arrived }
        for (index, ride) in rides.enumerated() {
            if now < ride.departure.expectedTime {
                return index == 0 ? .waiting : .transfer(index: index)
            }
            if now < ride.arrival.expectedTime {
                return .riding(index: index)
            }
        }
        return .arrived
    }

    /// Die Fahrt, um die es gerade geht (bei Umstieg die nächste).
    public func focusRide(at now: Date) -> Ride? {
        switch phase(at: now) {
        case .waiting: rides.first
        case .riding(let i), .transfer(let i): rides[i]
        case .arrived: rides.last
        }
    }

    /// Zeitpunkt, auf den der Countdown gerade zuläuft.
    public func countdownTarget(at now: Date) -> Date? {
        switch phase(at: now) {
        case .waiting: rides.first?.departure.expectedTime
        case .transfer(let i): rides[i].departure.expectedTime
        case .riding(let i): rides[i].arrival.expectedTime
        case .arrived: nil
        }
    }
}

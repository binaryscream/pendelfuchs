// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Wo befindet sich eine Fahrt gerade? Berechnet aus Plan-/Echtzeitdaten und der aktuellen Uhrzeit.
public enum RideProgress: Equatable, Sendable {
    case notStarted
    /// Zwischen Halt `passed` und `passed + 1`; `fraction` 0…1 auf dem Abschnitt.
    case underway(passed: Int, fraction: Double)
    case finished

    /// Wurde Halt `index` schon passiert (abgefahren bzw. beim letzten Halt: angekommen)?
    public func hasPassed(_ index: Int) -> Bool {
        switch self {
        case .notStarted: false
        case .underway(let passed, _): index <= passed
        case .finished: true
        }
    }
}

extension TripLeg {
    public func progress(at now: Date) -> RideProgress {
        let times = stops.enumerated().map { index, stop -> Date? in
            // Abfahrt zählt, außer beim letzten Halt (dort die Ankunft).
            index == stops.count - 1 ? (stop.arrival ?? stop.departure)?.expectedTime : stop.passTime
        }
        guard let first = times.first ?? nil, let last = times.last ?? nil else { return .notStarted }
        if now < first { return .notStarted }
        if now >= last { return .finished }

        var passed = 0
        for (index, time) in times.enumerated() {
            if let time, time <= now { passed = index }
        }
        guard passed + 1 < times.count, let from = times[passed], let to = times[passed + 1], to > from else {
            return .underway(passed: passed, fraction: 0)
        }
        // Ankunft am nächsten Halt ist das eigentliche Ziel des Abschnitts.
        let target = stops[passed + 1].arrival?.expectedTime ?? to
        let fraction = min(1, max(0, now.timeIntervalSince(from) / max(1, target.timeIntervalSince(from))))
        return .underway(passed: passed, fraction: fraction)
    }

    /// Geschätzte Position des Fahrzeugs (entlang der Strecke, sonst Luftlinie zwischen den Halten).
    public func estimatedPosition(at now: Date) -> Coordinate? {
        guard case .underway(let passed, let fraction) = progress(at: now),
              let a = stops[passed].coordinate, let b = stops[passed + 1].coordinate
        else { return nil }

        let line = drawablePath
        if line.count >= 2 {
            let startIndex = Geo.nearestIndex(to: a, in: line)
            let endIndex = Geo.nearestIndex(to: b, in: line)
            if endIndex > startIndex {
                return Geo.point(along: Array(line[startIndex...endIndex]), fraction: fraction)
            }
        }
        return Geo.point(along: [a, b], fraction: fraction)
    }
}

extension Trip {
    /// Anteil der gesamten Fahrt (0…1), `nil` vor der Abfahrt.
    public func overallProgress(at now: Date) -> Double? {
        let start = departure.expectedTime
        let end = arrival.expectedTime
        guard now >= start, end > start else { return nil }
        return min(1, now.timeIntervalSince(start) / end.timeIntervalSince(start))
    }
}

/// Kleine Geometrie-Helfer (Kugelnäherung, für Anzeigezwecke genau genug).
public enum Geo {
    public static func meters(_ a: Coordinate, _ b: Coordinate) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    static func nearestIndex(to point: Coordinate, in line: [Coordinate]) -> Int {
        line.indices.min { meters(line[$0], point) < meters(line[$1], point) } ?? 0
    }

    /// Punkt nach `fraction` (0…1) der Länge einer Linie.
    static func point(along line: [Coordinate], fraction: Double) -> Coordinate? {
        guard let first = line.first else { return nil }
        guard line.count > 1 else { return first }
        let segments = zip(line, line.dropFirst()).map { meters($0, $1) }
        let total = segments.reduce(0, +)
        guard total > 0 else { return first }
        var remaining = total * min(1, max(0, fraction))
        for (index, length) in segments.enumerated() {
            if remaining <= length || index == segments.count - 1 {
                let t = length > 0 ? min(1, remaining / length) : 0
                let a = line[index], b = line[index + 1]
                return Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                  longitude: a.longitude + (b.longitude - a.longitude) * t)
            }
            remaining -= length
        }
        return line.last
    }

    /// Dekodiert eine „Encoded Polyline“ (Google-Format) mit der angegebenen Genauigkeit (5 oder 6 Stellen).
    public static func decodePolyline(_ encoded: String, precision: Int = 5) -> [Coordinate] {
        let factor = pow(10.0, Double(precision))
        var coordinates: [Coordinate] = []
        var index = encoded.unicodeScalars.startIndex
        let scalars = encoded.unicodeScalars
        var lat = 0, lon = 0

        func nextValue() -> Int? {
            var result = 0, shift = 0
            while index < scalars.endIndex {
                let byte = Int(scalars[index].value) - 63
                index = scalars.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }

        while index < scalars.endIndex {
            guard let dLat = nextValue(), let dLon = nextValue() else { break }
            lat += dLat
            lon += dLon
            coordinates.append(Coordinate(latitude: Double(lat) / factor, longitude: Double(lon) / factor))
        }
        return coordinates
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Zuletzt gemeldete Position eines Fahrzeugs aus dem TLMS-Live-Feed (Dresden).
///
/// TLMS (tlm.solutions) empfängt die R09-Funktelegramme, die Straßenbahnen und Busse der DVB an Meldepunkten
/// (Ampeln, Haltestellen) senden. Positionen gibt es also nur punktweise, nicht als GPS-Spur.
public struct LiveVehicle: Sendable, Hashable {
    public var line: Int
    /// Umlaufnummer – zusammen mit der Linie eindeutig für ein Fahrzeug.
    public var run: Int
    public var coordinate: Coordinate
    public var reportedAt: Date
    /// Verspätung in Sekunden (negativ: zu früh), falls gemeldet.
    public var delay: TimeInterval?

    public init(line: Int, run: Int, coordinate: Coordinate, reportedAt: Date, delay: TimeInterval? = nil) {
        self.line = line
        self.run = run
        self.coordinate = coordinate
        self.reportedAt = reportedAt
        self.delay = delay
    }
}

/// Liest die Fahrzeugpositionen von TLMS (`lizard.tlm.solutions`, Region 0 = Dresden).
public struct TLMSClient: Sendable {
    private let url: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "https://lizard.tlm.solutions")!, region: Int = 0,
                session: URLSession = .shared) {
        self.url = baseURL.appending(path: "v1/vehicles/\(region)")
        self.session = session
    }

    public func vehicles() async throws -> [LiveVehicle] {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [LiveVehicle] {
        struct Waypoint: Decodable {
            var time: Double
            var lat: Double
            var lon: Double
            var line: Int?
            var run: Int?
            var delayed: Double?
        }
        return try JSONDecoder().decode([Waypoint].self, from: data).compactMap { point in
            guard let line = point.line, let run = point.run else { return nil }
            return LiveVehicle(line: line, run: run,
                               coordinate: Coordinate(latitude: point.lat, longitude: point.lon),
                               reportedAt: Date(timeIntervalSince1970: point.time / 1000),
                               delay: point.delayed)
        }
    }
}

/// Ein Fahrzeug aus dem Live-Feed, das zu einer Fahrt passt, samt seiner Lage auf deren Strecke.
public struct LiveVehicleMatch: Sendable, Hashable {
    public var vehicle: LiveVehicle
    /// Meter entlang des Streckenverlaufs der Fahrt, an denen das Fahrzeug gemeldet wurde.
    public var offset: Double
}

/// Live-Zustand einer Fahrt laut TLMS.
public struct LiveRideState: Sendable, Hashable {
    public var vehicle: LiveVehicle
    /// Vermutete Position jetzt (gemeldete Lage, bis zum nächsten Halt weitergerückt).
    public var position: Coordinate
    /// Fortschritt auf der Fahrt (vor dem Einstieg: `.notStarted`).
    public var progress: RideProgress
    /// Noch nicht am Einstieg: so viele Halte ist das Fahrzeug noch entfernt (0: kommt gleich / steht am Start).
    public var stopsAway: Int?
}

extension TripLeg {
    /// Liniennummer im TLMS-Feed, wenn diese Fahrt dort vorkommen kann (Straßenbahn/Stadtbus in Dresden).
    public var tlmsLine: Int? {
        guard kind == .ride, mode == .tram || mode == .cityBus,
              let line, let number = Int(line.trimmingCharacters(in: .whitespaces)),
              stops.contains(where: { $0.coordinate.map(TLMSArea.contains) ?? false })
        else { return nil }
        return number
    }

    /// Sucht das Fahrzeug, das diese Fahrt gerade fährt.
    ///
    /// Kandidaten sind Fahrzeuge derselben Linie, die nah am Streckenverlauf gemeldet wurden. Gewählt wird das,
    /// dessen Lage am besten zu Fahrplan/Echtzeit passt (Abstand zur geschätzten Lage, ähnliche Verspätung).
    /// Fahrzeuge deutlich vor der erwarteten Lage gelten nicht – das ist in der Regel die vorige Fahrt.
    /// `preferredRun` hält ein einmal gefundenes Fahrzeug fest, solange es plausibel bleibt.
    public func liveMatch(in vehicles: [LiveVehicle], at now: Date, preferredRun: Int? = nil) -> LiveVehicleMatch? {
        guard let line = tlmsLine, !isFullyCancelled,
              let start = departure?.expectedTime, let end = arrival?.expectedTime,
              now >= start - 10 * 60, now <= end + 10 * 60
        else { return nil }
        let geometry = LegGeometry(self)
        guard geometry.length > 0 else { return nil }

        // Der Feed enthält mehrere Meldungen je Fahrzeug (die letzten Minuten) – nur die neueste zählt.
        var latest: [Int: LiveVehicle] = [:]
        for vehicle in vehicles where vehicle.line == line && now.timeIntervalSince(vehicle.reportedAt) <= 180 {
            if let known = latest[vehicle.run], known.reportedAt >= vehicle.reportedAt { continue }
            latest[vehicle.run] = vehicle
        }

        var best: (match: LiveVehicleMatch, score: Double)?
        for vehicle in latest.values.sorted(by: { $0.run < $1.run }) {
            guard let projection = Geo.project(vehicle.coordinate, onto: geometry.path),
                  projection.distance <= 120,
                  projection.offset >= geometry.stopOffsets[0] - 200,
                  projection.offset <= geometry.stopOffsets[geometry.stopOffsets.count - 1] + 50
            else { continue }

            let expected = geometry.expectedOffset(of: self, at: vehicle.reportedAt)
            // Hinter der erwarteten Lage darf ein Fahrzeug weit sein (Verspätung), davor kaum: Weiter vorn ist
            // meist die vorige Fahrt derselben Linie – etwa wenn diese Fahrt noch gar nicht losgefahren ist.
            let ahead = projection.offset - expected
            let gap = abs(ahead)
            let match = LiveVehicleMatch(vehicle: vehicle, offset: projection.offset)
            guard ahead <= 500 else { continue }
            if vehicle.run == preferredRun, gap <= 3000 { return match }
            guard gap <= 2000 else { continue }

            var score = gap
            if let reported = vehicle.delay, let known = currentDelay(at: vehicle.reportedAt) {
                // Eine Minute Unterschied in der Verspätung wiegt so viel wie 300 m Abstand.
                score += abs(reported - known) * 5
            }
            if best == nil || score < best!.score { best = (match, score) }
        }
        return best?.match
    }

    /// Position eines gefundenen Fahrzeugs jetzt: die gemeldete Lage, seitdem mit der Fahrplan-Geschwindigkeit
    /// des Abschnitts weitergerückt – höchstens bis zum nächsten Halt (dort könnte es warten).
    public func livePosition(of match: LiveVehicleMatch, at now: Date) -> Coordinate? {
        let geometry = LegGeometry(self)
        guard geometry.length > 0 else { return nil }
        return Geo.point(along: geometry.path, fraction: liveOffset(of: match, at: now, geometry: geometry) / geometry.length)
    }

    /// Meter entlang der Strecke, an denen das Fahrzeug jetzt vermutlich ist (siehe `livePosition`).
    func liveOffset(of match: LiveVehicleMatch, at now: Date, geometry: LegGeometry) -> Double {
        let offsets = geometry.stopOffsets
        let elapsed = max(0, now.timeIntervalSince(match.vehicle.reportedAt))
        guard let next = offsets.firstIndex(where: { $0 > match.offset + 1 }) else { return match.offset }
        var speed = 0.0
        if next > 0, let from = stops[next - 1].passTime,
           let to = (stops[next].arrival ?? stops[next].departure)?.expectedTime, to > from {
            speed = (offsets[next] - offsets[next - 1]) / to.timeIntervalSince(from)
        }
        return min(offsets[next], match.offset + speed * elapsed)
    }

    /// Fortschritt, wenn das Fahrzeug bei `offset` Metern entlang der Strecke steht.
    func progress(atOffset offset: Double, geometry: LegGeometry) -> RideProgress {
        let offsets = geometry.stopOffsets
        // Bis 15 m Abstand zählt ein Halt als erreicht (Meldepunkte liegen nicht genau am Haltepunkt).
        let tolerance = 15.0
        guard offsets.count >= 2, offset >= offsets[0] - tolerance else { return .notStarted }
        if offset >= offsets[offsets.count - 1] - tolerance { return .finished }
        var passed = 0
        for (index, stopOffset) in offsets.enumerated() where stopOffset <= offset + tolerance { passed = index }
        passed = min(passed, offsets.count - 2)
        let span = offsets[passed + 1] - offsets[passed]
        let fraction = span > 0 ? min(1, max(0, (offset - offsets[passed]) / span)) : 0
        return .underway(passed: passed, fraction: fraction)
    }

    /// Live-Zustand dieser Fahrt: wo das Fahrzeug ist und wie weit es auf der Fahrt ist.
    ///
    /// - Parameter run: der ganze Lauf des Fahrzeugs (Endhalt bis Endhalt), falls bekannt. Damit wird auch eine
    ///   Bahn erkannt, die noch zum Einstieg unterwegs ist; sonst nur ab dem Einstieg.
    public func liveState(in vehicles: [LiveVehicle], at now: Date, run: TripLeg? = nil,
                          preferredRun: Int? = nil) -> LiveRideState? {
        let boardIndex = run.flatMap(boardingIndex(in:))
        let tracked = boardIndex != nil ? run! : self
        let offsetInRun = boardIndex ?? 0

        guard let match = tracked.liveMatch(in: vehicles, at: now, preferredRun: preferredRun) else { return nil }
        let geometry = LegGeometry(tracked)
        guard geometry.length > 0 else { return nil }
        let offset = tracked.liveOffset(of: match, at: now, geometry: geometry)
        guard let position = Geo.point(along: geometry.path, fraction: offset / geometry.length) else { return nil }

        // Fortschritt auf dem ganzen Lauf in den Abschnitt dieser Fahrt umrechnen.
        let progress: RideProgress
        var stopsAway: Int?
        switch tracked.progress(atOffset: offset, geometry: geometry) {
        case .notStarted:
            progress = .notStarted
            if offsetInRun == 0 { stopsAway = 0 }
        case .finished:
            progress = .finished
        case .underway(let passed, let fraction):
            let relative = passed - offsetInRun
            if relative < 0 {
                progress = .notStarted
                stopsAway = -relative
            } else if relative >= stops.count - 1 {
                progress = .finished
            } else {
                progress = .underway(passed: relative, fraction: fraction)
            }
        }
        return LiveRideState(vehicle: match.vehicle, position: position, progress: progress, stopsAway: stopsAway)
    }

    /// Wo diese Fahrt im ganzen Lauf beginnt (gleicher Halt, gleiche Planzeit); `nil`, wenn nicht gefunden.
    func boardingIndex(in run: TripLeg) -> Int? {
        guard let first = stops.first, let scheduled = departure?.scheduledTime else { return nil }
        return run.stops.firstIndex { stop in
            guard let time = (stop.departure ?? stop.arrival)?.scheduledTime,
                  abs(time.timeIntervalSince(scheduled)) < 90 else { return false }
            return stop.stopID == first.stopID || stop.name == first.name
                || stop.name.hasSuffix(first.name) || first.name.hasSuffix(stop.name)
                || stop.coordinate.flatMap { a in first.coordinate.map { Geo.meters(a, $0) < 150 } } == true
        }
    }

    /// Stabiler Schlüssel einer Fahrt, um das einmal gefundene Fahrzeug festzuhalten.
    public var liveKey: String {
        "\(line ?? "")|\(stops.first?.name ?? "")|\(Int(departure?.scheduledTime.timeIntervalSince1970 ?? 0))"
    }

    /// Verspätung (Sekunden) laut Echtzeit am nächsten Halt nach `date`, falls bekannt.
    func currentDelay(at date: Date) -> TimeInterval? {
        let upcoming = stops.first { ($0.passTime ?? .distantPast) >= date } ?? stops.last
        guard let point = upcoming?.departure ?? upcoming?.arrival, let realTime = point.realTime else { return nil }
        return realTime.timeIntervalSince(point.scheduledTime)
    }
}

/// Grobes Rechteck um das Gebiet, das TLMS in Region 0 abdeckt (Dresden und direkte Umgebung).
enum TLMSArea {
    static func contains(_ coordinate: Coordinate) -> Bool {
        (50.95...51.15).contains(coordinate.latitude) && (13.55...13.95).contains(coordinate.longitude)
    }
}

/// Streckenverlauf einer Fahrt mit der Lage (Meter entlang der Strecke) jedes Halts.
struct LegGeometry {
    let path: [Coordinate]
    let length: Double
    /// Pro Halt die Meter entlang der Strecke (aufsteigend; Halte ohne Koordinate erben den vorigen Wert).
    let stopOffsets: [Double]

    init(_ leg: TripLeg) {
        path = leg.drawablePath
        length = zip(path, path.dropFirst()).reduce(0) { $0 + Geo.meters($1.0, $1.1) }
        var offsets: [Double] = []
        var segment = 0
        for stop in leg.stops {
            let previous = offsets.last ?? 0
            if let coordinate = stop.coordinate,
               let projection = Geo.project(coordinate, onto: path, fromSegment: segment) {
                segment = projection.segment
                offsets.append(max(previous, projection.offset))
            } else {
                offsets.append(previous)
            }
        }
        stopOffsets = offsets.isEmpty ? [0] : offsets
    }

    /// Wo das Fahrzeug laut Fahrplan/Echtzeit zu `date` sein sollte (Meter entlang der Strecke).
    func expectedOffset(of leg: TripLeg, at date: Date) -> Double {
        switch leg.progress(at: date) {
        case .notStarted: return stopOffsets[0]
        case .finished: return stopOffsets[stopOffsets.count - 1]
        case .underway(let passed, let fraction):
            let from = stopOffsets[passed]
            let to = stopOffsets[min(passed + 1, stopOffsets.count - 1)]
            return from + (to - from) * fraction
        }
    }
}

extension Geo {
    struct PathProjection {
        /// Meter vom Anfang der Linie bis zum Lotfußpunkt.
        var offset: Double
        /// Abstand des Punkts von der Linie in Metern.
        var distance: Double
        /// Index des Liniensegments mit dem Lotfußpunkt.
        var segment: Int
    }

    /// Projiziert einen Punkt auf die nächstgelegene Stelle einer Linie (ab Segment `fromSegment`).
    static func project(_ point: Coordinate, onto line: [Coordinate], fromSegment: Int = 0) -> PathProjection? {
        guard line.count >= 2, fromSegment < line.count - 1 else { return nil }
        // Lokale ebene Näherung in Metern um den Punkt – für Stadtgebiete genau genug.
        let metersPerDegreeLat = 111_195.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(point.latitude * .pi / 180)
        func xy(_ c: Coordinate) -> (x: Double, y: Double) {
            ((c.longitude - point.longitude) * metersPerDegreeLon, (c.latitude - point.latitude) * metersPerDegreeLat)
        }

        var best: PathProjection?
        var travelled = 0.0
        for index in 0..<(line.count - 1) {
            let a = xy(line[index]), b = xy(line[index + 1])
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            // Längen wie im Rest der App (Kugelnäherung), damit Offsets zu `Geo.point(along:)` passen.
            let length = meters(line[index], line[index + 1])
            if index >= fromSegment {
                let t = lengthSquared > 0 ? min(1, max(0, -(a.x * dx + a.y * dy) / lengthSquared)) : 0
                let px = a.x + dx * t, py = a.y + dy * t
                let distance = (px * px + py * py).squareRoot()
                if best == nil || distance < best!.distance {
                    best = PathProjection(offset: travelled + length * t, distance: distance, segment: index)
                }
            }
            travelled += length
        }
        return best
    }
}

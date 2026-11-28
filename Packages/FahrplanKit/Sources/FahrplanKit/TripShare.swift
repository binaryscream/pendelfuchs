// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension Trip {
    /// Die Verbindung als Text zum Teilen (Nachricht, Mail) – lesbar auch ohne die App:
    ///
    ///     Pirna Bahnhof → Dresden Postplatz
    ///     Sa. 28. Nov. · 18:36–19:07 · 1 Umstieg
    ///
    ///     S1  18:36 Pirna Bahnhof (Gl. 1) → 18:58 Dresden Hauptbahnhof
    ///     7  19:02 Dresden Hauptbahnhof (Steig 3) → 19:07 Dresden Postplatz
    ///
    /// Zeiten laut Fahrplan; eine aktuelle Verspätung steht als „(+4)“ dahinter, ein Ausfall als „fällt aus“.
    public func shareText(style: StopNameStyle = .withPlace, timeZone: TimeZone = .current) -> String {
        let rides = rides
        guard let first = rides.first?.stops.first, let last = rides.last?.stops.last else { return "" }

        let locale = Locale(identifier: "de_DE")
        var time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        time.timeZone = timeZone
        var day = Date.FormatStyle(locale: locale).weekday(.abbreviated).day().month(.abbreviated)
        day.timeZone = timeZone

        func clock(_ point: TimePoint) -> String {
            let delay = point.delayMinutes ?? 0
            return point.scheduledTime.formatted(time) + (delay >= 1 ? " (+\(delay))" : "")
        }

        let changes = rides.count - 1
        var header = "\(departure.scheduledTime.formatted(day)) · "
            + "\(departure.scheduledTime.formatted(time))–\(arrival.scheduledTime.formatted(time))"
        header += changes == 0 ? " · ohne Umstieg" : changes == 1 ? " · 1 Umstieg" : " · \(changes) Umstiege"

        let lines = rides.compactMap { ride -> String? in
            guard let from = ride.stops.first, let to = ride.stops.last,
                  let departure = ride.departure, let arrival = ride.arrival else { return nil }
            let usesTracks = ride.mode == .train || ride.mode == .suburbanRailway || ride.mode == .longDistance
            let platform = from.platform.map { " (\(usesTracks ? "Gl." : "Steig") \($0))" } ?? ""
            let line = [ride.line, ride.isCancelled ? "fällt aus:" : nil].compactMap { $0 }.joined(separator: " ")
            return "\(line)  \(clock(departure)) \(from.label(style))\(platform) → \(clock(arrival)) \(to.label(style))"
        }

        return (["\(first.label(style)) → \(last.label(style))", header, ""] + lines
                + ["", "Gefunden mit Pendelfuchs · pendelfuchs.de"]).joined(separator: "\n")
    }
}

extension TripQuery {
    /// Die Rückfahrt: Start und Ziel getauscht, gleicher Zwischenhalt und gleiche Suchoptionen, Abfahrt ab `time`.
    public func reversed(at time: Date = .now) -> TripQuery {
        TripQuery(origin: destination, destination: origin, via: via, time: time, isArrivalTime: false,
                  options: options)
    }
}

extension SavedTrip {
    /// Suche für die Rückfahrt einer gemerkten Fahrt, mit deren Suchoptionen.
    public func returnQuery(at time: Date = .now) -> TripQuery {
        TripQuery(origin: destination, destination: origin, via: via, time: time, isArrivalTime: false,
                  options: options)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension VVOProvider {
    /// Verbindungssuche über `/tr/trips`.
    ///
    /// Hinweis: Der Zwischenhalt heißt in der API `Via` (groß geschrieben) – `via` wird stillschweigend ignoriert.
    public func trips(_ query: TripQuery) async throws -> [Trip] {
        var body: [String: any Sendable] = [
            "origin": query.origin.stopID,
            "destination": query.destination.stopID,
            "time": VVODecoding.requestTime(query.time),
            "isarrivaltime": query.isArrivalTime,
            "shorttermchanges": true,
        ]
        if let via = query.via { body["Via"] = via.stopID }
        let response: TripsResponse = try await post("tr/trips", body: body)
        return response.trips
    }
}

extension VVODecoding {
    /// Zeit im Format `2026-11-24T06:30:00+01:00` (deutsche Ortszeit, die API rechnet in Ortszeit).
    static func requestTime(_ date: Date) -> String {
        var style = Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        style = style.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .colon)
        return date.formatted(style)
    }

    static func mode(_ mot: String?) -> TransportMode {
        switch mot {
        case "Tram": .tram
        case "CityBus", "Bus": .cityBus
        case "IntercityBus", "PlusBus": .regionalBus
        case "SuburbanRailway", "RapidTransit": .suburbanRailway
        case "Train": .train
        case "Cableway": .cableway
        case "Ferry": .ferry
        case "HailedSharedTaxi": .onDemand
        default: .other
        }
    }
}

struct TripsResponse: Decodable, StatusCarrying {
    let status: VVOStatus
    let routes: [Route]

    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case routes = "Routes"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(VVOStatus.self, forKey: .status)
        routes = try c.decodeIfPresent([Route].self, forKey: .routes) ?? []
    }

    var trips: [Trip] {
        routes.compactMap(\.trip).sorted { $0.departure.expectedTime < $1.departure.expectedTime }
    }

    struct Route: Decodable {
        let interchanges: Int?
        let price: String?
        let fareZoneNames: String?
        let partialRoutes: [PartialRoute]

        enum CodingKeys: String, CodingKey {
            case interchanges = "Interchanges"
            case price = "Price"
            case fareZoneNames = "FareZoneNames"
            case partialRoutes = "PartialRoutes"
        }

        var trip: Trip? {
            var legs: [TripLeg] = []
            for partial in partialRoutes {
                guard let leg = partial.leg else { continue }
                // Aufeinanderfolgende Fußwege zusammenfassen.
                if leg.kind == .walk, let last = legs.last, last.kind == .walk {
                    legs[legs.count - 1].durationMinutes = (last.durationMinutes ?? 0) + (leg.durationMinutes ?? 0)
                    continue
                }
                legs.append(leg)
            }
            // Fußwege ohne Dauer am Anfang/Ende sind Rauschen.
            while let first = legs.first, first.kind == .walk, (first.durationMinutes ?? 0) == 0 { legs.removeFirst() }
            while let last = legs.last, last.kind == .walk, (last.durationMinutes ?? 0) == 0 { legs.removeLast() }
            guard legs.contains(where: { $0.kind == .ride }) else { return nil }

            let rides = legs.filter { $0.kind == .ride }.count
            return Trip(
                legs: legs,
                interchanges: interchanges ?? max(0, rides - 1),
                price: price.flatMap { $0.isEmpty ? nil : "\($0) €" },
                fareZones: fareZoneNames.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }

    struct PartialRoute: Decodable {
        let duration: Int?
        let mot: Mot
        let infos: [String]?
        let regularStops: [RegularStop]?

        enum CodingKeys: String, CodingKey {
            case duration = "Duration"
            case mot = "Mot"
            case infos = "Infos"
            case regularStops = "RegularStops"
        }

        struct Mot: Decodable {
            let type: String?
            let name: String?
            let direction: String?
            let transportationCompany: String?

            enum CodingKeys: String, CodingKey {
                case type = "Type"
                case name = "Name"
                case direction = "Direction"
                case transportationCompany = "TransportationCompany"
            }
        }

        var leg: TripLeg? {
            switch mot.type {
            case "Footpath":
                return TripLeg(kind: .walk, durationMinutes: duration ?? 0)
            case "MobilityStairsUp", "MobilityStairsDown", "MobilityEscalatorUp", "MobilityEscalatorDown",
                 "MobilityElevatorUp", "MobilityElevatorDown", "MobilityRampUp", "MobilityRampDown":
                // Treppen-/Aufzugshinweise: als Fußweg ohne Dauer behandeln.
                return TripLeg(kind: .walk, durationMinutes: duration ?? 0)
            default:
                let stops = (regularStops ?? []).compactMap(\.tripStop)
                guard stops.count >= 2 else { return nil }
                return TripLeg(
                    kind: .ride,
                    mode: VVODecoding.mode(mot.type),
                    line: mot.name,
                    direction: mot.direction,
                    operatorName: mot.transportationCompany,
                    stops: stops,
                    durationMinutes: duration,
                    notes: infos ?? []
                )
            }
        }
    }

    struct RegularStop: Decodable {
        let dataId: String?
        let name: String
        let place: String?
        let platform: Platform?
        let arrivalTime: String?
        let arrivalRealTime: String?
        let departureTime: String?
        let departureRealTime: String?
        let departureState: String?
        let arrivalState: String?
        let cancelReasons: [String]?

        struct Platform: Decodable {
            let name: String?
            enum CodingKeys: String, CodingKey { case name = "Name" }
        }

        enum CodingKeys: String, CodingKey {
            case dataId = "DataId"
            case name = "Name"
            case place = "Place"
            case platform = "Platform"
            case arrivalTime = "ArrivalTime"
            case arrivalRealTime = "ArrivalRealTime"
            case departureTime = "DepartureTime"
            case departureRealTime = "DepartureRealTime"
            case departureState = "DepartureState"
            case arrivalState = "ArrivalState"
            case cancelReasons = "CancelReasons"
        }

        var tripStop: TripStop? {
            func point(_ scheduled: String?, _ real: String?) -> TimePoint? {
                guard let s = scheduled.flatMap(VVODecoding.parseDate) else { return nil }
                return TimePoint(scheduledTime: s, realTime: real.flatMap(VVODecoding.parseDate))
            }
            let cancelled = departureState == "Cancelled" || arrivalState == "Cancelled" || !(cancelReasons ?? []).isEmpty
            return TripStop(
                stopID: dataId ?? "",
                name: name,
                place: place,
                platform: platform?.name,
                arrival: point(arrivalTime, arrivalRealTime),
                departure: point(departureTime, departureRealTime),
                isCancelled: cancelled
            )
        }
    }
}

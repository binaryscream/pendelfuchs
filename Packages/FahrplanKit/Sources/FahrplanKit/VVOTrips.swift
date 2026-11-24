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
        let options = query.options
        let settings: [String: any Sendable] = [
            "walkingSpeed": options.walkingSpeed.vvoValue,
            "maxChanges": VVODecoding.maxChanges(options.maxTransfers),
        ]

        func fetch(_ settings: [String: any Sendable]) async throws -> [Trip] {
            var body = body
            body["standardSettings"] = settings
            let response: TripsResponse = try await post("tr/trips", body: body)
            return response.trips
        }

        var found: [Trip]
        if let mots = VVODecoding.mots(for: options.allowedModes) {
            var filtered = settings
            filtered["mot"] = mots
            found = try await fetch(filtered)
            // Schienenersatzverkehr (SEV) gehört zu keinem Verkehrsmittel-Filter der API und fiele sonst weg.
            // Deshalb zusätzlich ohne Filter fragen und lokal filtern.
            if options.allowedModes.contains(.bus) {
                let known = Set(found.map(\.id))
                found += try await fetch(settings).filter { !known.contains($0.id) }
            }
        } else {
            // Nichts, was die API selbst filtern könnte (z. B. nur „ohne Fernverkehr“): lokal filtern – so bleibt
            // auch der SEV erhalten.
            found = try await fetch(settings)
        }
        return found.filter(options.allows).sorted { $0.departure.expectedTime < $1.departure.expectedTime }
    }
}

extension VVODecoding {
    /// Zeit im Format `2026-11-24T06:30:00+01:00` (deutsche Ortszeit, die API rechnet in Ortszeit).
    static func requestTime(_ date: Date) -> String {
        var style = Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        style = style.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .colon)
        return date.formatted(style)
    }

    /// Verkehrsmittel inkl. Fernverkehrserkennung über den Linienname (VVO meldet ICE/IC nur als „Train“).
    static func mode(_ mot: String?, line: String?) -> TransportMode {
        let base = mode(mot)
        if base == .train, let line, TransportMode.isLongDistanceName(line) { return .longDistance }
        return base
    }

    /// VVO-Verkehrsmittel (`standardSettings.mot`) für die erlaubten Gruppen.
    /// `nil`, wenn die API nichts filtern muss: Fernzug und Fernbus kennt sie nicht als eigenes Verkehrsmittel
    /// (Fernzüge laufen unter „Train“) – das erledigt der lokale Filter.
    static func mots(for groups: Set<ModeGroup>) -> [String]? {
        let vvoGroups = Set(ModeGroup.allCases).subtracting([.longDistance, .coach])
        if vvoGroups.isSubset(of: groups) { return nil }

        var mots: [String] = []
        if groups.contains(.tram) { mots.append("Tram") }
        if groups.contains(.bus) { mots += ["CityBus", "IntercityBus"] }
        if groups.contains(.regionalRail) { mots.append("SuburbanRailway") }
        // Regional- und Fernzüge laufen beim VVO beide unter „Train“; Fernzüge filtert die App danach heraus.
        if groups.contains(.regionalRail) || groups.contains(.longDistance) { mots.append("Train") }
        if groups.contains(.cableway) { mots.append("Cableway") }
        if groups.contains(.ferry) { mots.append("Ferry") }
        if groups.contains(.onDemand) { mots.append("HailedSharedTaxi") }
        return mots
    }

    /// `standardSettings.maxChanges`: „None“, „One“, „Two“ oder „Unlimited“ (drei Umstiege kennt die API nicht).
    static func maxChanges(_ transfers: Int?) -> String {
        switch transfers {
        case 0: "None"
        case 1: "One"
        case 2: "Two"
        default: "Unlimited"
        }
    }

    /// `/Date(1795470720000-0000)/`
    static func dotNetDate(_ date: Date) -> String {
        "/Date(\(Int64((date.timeIntervalSince1970 * 1000).rounded()))-0000)/"
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
        let mapData: [String]?

        enum CodingKeys: String, CodingKey {
            case interchanges = "Interchanges"
            case price = "Price"
            case fareZoneNames = "FareZoneNames"
            case partialRoutes = "PartialRoutes"
            case mapData = "MapData"
        }

        var trip: Trip? {
            var legs: [TripLeg] = []
            var pendingNote: String?
            for partial in partialRoutes {
                // „Gesicherter Anschluss“: kein eigenes Verkehrsmittel, sondern Hinweis zur nächsten Fahrt.
                if partial.mot.type == "StayForConnection" {
                    pendingNote = "Anschluss wird abgewartet"
                    continue
                }
                guard var leg = partial.leg else { continue }
                if leg.kind == .ride, let note = pendingNote {
                    leg.notes.insert(note, at: 0)
                    pendingNote = nil
                }
                if let index = partial.mapDataIndex, let entry = mapData?[safe: index] {
                    leg.path = VVODecoding.path(fromMapData: entry)
                }
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
                fareZones: fareZoneNames.flatMap { $0.isEmpty ? nil : $0 },
                source: .vvo
            )
        }
    }

    struct PartialRoute: Decodable {
        let duration: Int?
        let mapDataIndex: Int?
        let mot: Mot
        let infos: [String]?
        let regularStops: [RegularStop]?

        enum CodingKeys: String, CodingKey {
            case duration = "Duration"
            case mapDataIndex = "MapDataIndex"
            case mot = "Mot"
            case infos = "Infos"
            case regularStops = "RegularStops"
        }

        struct Mot: Decodable {
            let type: String?
            let name: String?
            let direction: String?
            let transportationCompany: String?
            let productName: String?
            let trainNumber: String?

            enum CodingKeys: String, CodingKey {
                case trainNumber = "TrainNumber"
                case productName = "ProductName"
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
            case "Bus" where mot.productName == "Ersatzverkehr" || (mot.name ?? "").hasPrefix("SEV"):
                // Schienenersatzverkehr: ein Bus, der eine Bahn ersetzt (VVO meldet nur „Bus“).
                let stops = (regularStops ?? []).compactMap(\.tripStop)
                guard stops.count >= 2 else { return nil }
                return TripLeg(kind: .ride, mode: .regionalBus, line: mot.name, direction: mot.direction,
                               operatorName: mot.transportationCompany, stops: stops, durationMinutes: duration,
                               notes: ["Schienenersatzverkehr"] + (infos ?? []))
            case "MobilityStairsUp", "MobilityStairsDown", "MobilityEscalatorUp", "MobilityEscalatorDown",
                 "MobilityElevatorUp", "MobilityElevatorDown", "MobilityRampUp", "MobilityRampDown":
                // Treppen-/Aufzugshinweise: als Fußweg ohne Dauer behandeln.
                return TripLeg(kind: .walk, durationMinutes: duration ?? 0)
            default:
                let stops = (regularStops ?? []).compactMap(\.tripStop)
                guard stops.count >= 2 else { return nil }
                return TripLeg(
                    kind: .ride,
                    mode: VVODecoding.mode(mot.type, line: mot.name),
                    line: mot.name,
                    direction: mot.direction,
                    operatorName: mot.transportationCompany,
                    stops: stops,
                    durationMinutes: duration,
                    notes: infos ?? [],
                    trainNumber: mot.trainNumber.flatMap { $0.isEmpty ? nil : $0 }
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
        let occupancy: String?
        /// Achtung: trotz des Namens GK4-Hochwert bzw. -Rechtswert.
        let latitude: Double?
        let longitude: Double?

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
            case occupancy = "Occupancy"
            case latitude = "Latitude"
            case longitude = "Longitude"
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
                isCancelled: cancelled,
                coordinate: VVODecoding.coordinate(northing: latitude, easting: longitude),
                occupancy: DepartureMonitorResponse.RawDeparture.occupancy(occupancy)
            )
        }
    }
}


extension VVODecoding {
    /// GK4-Koordinate der VVO-API → WGS84 (0/fehlend → nil).
    static func coordinate(northing: Double?, easting: Double?) -> Coordinate? {
        guard let northing, let easting, northing > 0, easting > 0 else { return nil }
        return GaussKrueger.toWGS84(.init(easting: easting, northing: northing))
    }

    /// `"Tram|5659228|4620896|5659216|4620911|…"` → Koordinaten (Hochwert/Rechtswert-Paare in GK4).
    static func path(fromMapData entry: String) -> [Coordinate] {
        let numbers = entry.split(separator: "|").dropFirst().compactMap { Double($0) }
        return stride(from: 0, to: numbers.count - 1, by: 2).compactMap {
            coordinate(northing: numbers[$0], easting: numbers[$0 + 1])
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}


/// Antwort von `/dm/trip`: alle Halte einer Fahrt mit Plan-/Echtzeit und Strecke.
struct JourneyResponse: Decodable, StatusCarrying {
    let status: VVOStatus
    let stops: [JourneyStop]
    let mapData: [String]?

    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case stops = "Stops"
        case mapData = "MapData"
    }

    struct JourneyStop: Decodable {
        let id: String?
        let place: String?
        let name: String
        let latitude: Double?
        let longitude: Double?
        let platform: Platform?
        let time: String?
        let realTime: String?
        let state: String?
        let occupancy: String?

        struct Platform: Decodable {
            let name: String?
            enum CodingKeys: String, CodingKey { case name = "Name" }
        }

        enum CodingKeys: String, CodingKey {
            case occupancy = "Occupancy"
            case id = "Id"
            case place = "Place"
            case name = "Name"
            case latitude = "Latitude"
            case longitude = "Longitude"
            case platform = "Platform"
            case time = "Time"
            case realTime = "RealTime"
            case state = "State"
        }

        var tripStop: TripStop? {
            guard let scheduled = time.flatMap(VVODecoding.parseDate) else { return nil }
            // Die API liefert nur eine Zeit je Halt – sie gilt für Ankunft und Abfahrt.
            let point = TimePoint(scheduledTime: scheduled, realTime: realTime.flatMap(VVODecoding.parseDate))
            // Im Fahrtverlauf steht der Ort bereits im Namen („Pirna Bahnhof“); leer heißt hier nicht „Dresden“.
            return TripStop(stopID: id ?? "", name: name, place: place.flatMap { $0.isEmpty ? nil : $0 },
                            platform: platform?.name, arrival: point, departure: point,
                            isCancelled: state == "Cancelled",
                            coordinate: VVODecoding.coordinate(northing: latitude, easting: longitude),
                            occupancy: DepartureMonitorResponse.RawDeparture.occupancy(occupancy))
        }
    }

    func leg(line: String, direction: String, mode: TransportMode) -> TripLeg {
        TripLeg(kind: .ride, mode: mode, line: line, direction: direction,
                stops: stops.compactMap(\.tripStop),
                path: mapData?.first.map(VVODecoding.path(fromMapData:)) ?? [])
    }
}

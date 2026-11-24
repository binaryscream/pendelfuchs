// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Zugriff auf die (inoffizielle) Web-Schnittstelle von bahn.de – für Wagenreihung und Auslastung.
/// Kann jederzeit ausfallen oder sich ändern; Fehler sollen die App nie blockieren.
struct DBWebClient: Sendable {
    let session: URLSession
    private let baseURL = URL(string: "https://www.bahn.de/web/api/")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// `nil` bei 404/204 (nichts bekannt).
    func get(_ path: String, _ params: [String: String]) async throws -> Data? {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("de", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 || status == 204 { return nil }
        guard (200..<300).contains(status) else { throw TransitError.badResponse(status: status) }
        return data
    }

    /// DB-Bahnhofsnummer (EVA) des nächsten Bahnhofs mit Zügen im Umkreis von 1 km.
    func evaNumber(near coordinate: Coordinate) async throws -> String? {
        let key = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
        if let cached = await DBCache.shared.eva(for: key) { return cached }
        guard let data = try await get("reiseloesung/orte/nearby", [
            "lat": String(coordinate.latitude), "long": String(coordinate.longitude), "radius": "1000", "maxNo": "10",
        ]) else { return nil }
        let eva = try DBDecoding.trainStation(from: data)
        if let eva { await DBCache.shared.setEva(eva, for: key) }
        return eva
    }

    static var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
}

actor DBCache {
    static let shared = DBCache()
    private var evas: [String: String] = [:]
    private var occupancy: [String: (Date, [String: Occupancy])] = [:]

    func eva(for key: String) -> String? { evas[key] }
    func setEva(_ value: String, for key: String) { evas[key] = value }

    /// Auslastung einer Fahrt, 5 Minuten zwischengespeichert.
    func occupancy(for key: String) -> [String: Occupancy]? {
        guard let (date, value) = occupancy[key], date.timeIntervalSinceNow > -300 else { return nil }
        return value
    }
    func setOccupancy(_ value: [String: Occupancy], for key: String) { occupancy[key] = (.now, value) }
}

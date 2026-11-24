// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import Foundation

/// Gemeinsamer Speicher von App und Widget-Erweiterung (Favoriten, gemerkte Fahrten).
enum AppGroup {
    static let id = "group.de.fahrplanxl.app"

    /// Fällt auf `.standard` zurück, falls die App Group (z. B. ohne Signatur) nicht verfügbar ist.
    /// Ein gemeinsames Objekt für die ganze Anwendung: Mit je einem neuen `UserDefaults` pro Zugriff bemerkt
    /// SwiftUI (`@AppStorage`) Änderungen aus anderen Ansichten nicht sofort. `UserDefaults` ist thread-sicher.
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard

    /// Schlüssel, die früher in `UserDefaults.standard` lagen.
    private static let migratedKeys = ["favoriteStops.v1", "savedTrips.v1"]

    /// Übernimmt einmalig Daten aus dem alten App-eigenen Speicher in die App Group.
    static func migrateFromStandardDefaults() {
        let standard = UserDefaults.standard
        guard let group = UserDefaults(suiteName: id) else { return }
        for key in migratedKeys where group.object(forKey: key) == nil {
            if let value = standard.object(forKey: key) {
                group.set(value, forKey: key)
            }
        }
    }
}

/// Deep Links, z. B. aus dem Widget: `fahrplanxl://stop?s=<Haltestelle als Base64-JSON>`.
enum DeepLink {
    static let scheme = "fahrplanxl"

    static func url(for stop: Stop) -> URL? {
        guard let token = StopToken.encode(stop) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "stop"
        components.queryItems = [URLQueryItem(name: "s", value: token)]
        return components.url
    }

    /// Strecke für die Verbindungssuche: `fahrplanxl://route?o=<Start>&d=<Ziel>`.
    static func url(forRoute from: Stop, _ to: Stop) -> URL? {
        guard let origin = StopToken.encode(from), let destination = StopToken.encode(to) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "route"
        components.queryItems = [URLQueryItem(name: "o", value: origin), URLQueryItem(name: "d", value: destination)]
        return components.url
    }

    static func route(from url: URL) -> (from: Stop, to: Stop)? {
        guard url.scheme == scheme, url.host == "route",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let o = items.first(where: { $0.name == "o" })?.value.flatMap(StopToken.decode),
              let d = items.first(where: { $0.name == "d" })?.value.flatMap(StopToken.decode)
        else { return nil }
        return (o, d)
    }

    static func stop(from url: URL) -> Stop? {
        guard url.scheme == scheme, url.host == "stop",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "s" })?.value
        else { return nil }
        return StopToken.decode(token)
    }
}

/// Haltestelle als kompakter Text (Base64-URL von JSON) – für Deep Links und Widget-Konfiguration,
/// damit auch Haltestellen ohne Favoriten-Eintrag vollständig wiederhergestellt werden können.
enum StopToken {
    static func encode(_ stop: Stop) -> String? {
        var clean = stop
        clean.distance = nil
        clean.coordinate = nil
        // Feste Schlüsselreihenfolge: Ohne .sortedKeys ergibt dieselbe Haltestelle verschiedene Tokens,
        // und App Intents findet die im Widget gewählte Haltestelle nicht wieder.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(clean) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ token: String) -> Stop? {
        var base64 = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(Stop.self, from: data)
    }
}

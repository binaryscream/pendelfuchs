// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import Foundation

/// Gemeinsamer Speicher von App und Widget-Erweiterung (Favoriten, gemerkte Fahrten).
enum AppGroup {
    static let id = "group.de.fahrplanxl.app"

    /// Fällt auf `.standard` zurück, falls die App Group (z. B. ohne Signatur) nicht verfügbar ist.
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }

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

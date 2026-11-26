// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Wie Haltestellennamen angezeigt werden.
public enum StopNameStyle: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// Ort und Name zusammen: „Dresden Hbf“, „Pirna Bahnhof“.
    case withPlace
    /// Nur der Name wie von der Quelle geliefert („Hbf“, „Bahnhof“); in Listen steht der Ort klein darunter.
    case nameOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .withPlace: "Mit Ort"
        case .nameOnly: "Nur Name"
        }
    }

    public var example: String {
        switch self {
        case .withPlace: "Dresden Hbf · Pirna Bahnhof"
        case .nameOnly: "Hbf · Bahnhof"
        }
    }

    /// Ort und Name zu einer Bezeichnung zusammensetzen. Enthält der Name den Ort schon
    /// („Dresden Hbf (Strehlener Str.)“, „Bern, Bahnhof“), bleibt er unverändert.
    public static func label(name: String, place: String?, style: StopNameStyle) -> String {
        guard style == .withPlace, let place = place?.trimmingCharacters(in: .whitespaces), !place.isEmpty else {
            return name
        }
        if name.localizedCaseInsensitiveContains(place) { return name }
        return "\(place) \(name)"
    }

    /// Zweite, kleine Zeile in Listen: der Ort – nur bei „Nur Name“ (sonst steht er schon im Namen).
    public static func secondaryLine(name: String, place: String?, style: StopNameStyle) -> String? {
        guard style == .nameOnly, let place = place?.trimmingCharacters(in: .whitespaces),
              !place.isEmpty, place != name else { return nil }
        return place
    }
}

extension Stop {
    public func label(_ style: StopNameStyle) -> String {
        StopNameStyle.label(name: name, place: place, style: style)
    }

    public func secondaryLine(_ style: StopNameStyle) -> String? {
        StopNameStyle.secondaryLine(name: name, place: place, style: style)
    }
}

extension TripStop {
    public func label(_ style: StopNameStyle) -> String {
        StopNameStyle.label(name: name, place: place, style: style)
    }

    public func secondaryLine(_ style: StopNameStyle) -> String? {
        StopNameStyle.secondaryLine(name: name, place: place, style: style)
    }
}

extension String {
    /// Durchgehend großgeschriebene Ziele lesbar machen: „MESSE DRESDEN“ → „Messe Dresden“.
    /// Gängige Abkürzungen („HBF“, „TU“) und gemischt geschriebene Namen bleiben, wie sie sind.
    public var tidiedCase: String {
        let letters = unicodeScalars.filter(CharacterSet.letters.contains)
        guard letters.count >= 4, self == uppercased() else { return self }
        let abbreviations: Set<String> = ["HBF", "BF", "ZOB", "DB", "TU", "HTW", "UKD", "DD", "S", "U"]
        return split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            abbreviations.contains(String(word)) ? String(word) : word.split(separator: "-", omittingEmptySubsequences: false)
                .map { abbreviations.contains(String($0)) ? String($0) : $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: "-")
        }.joined(separator: " ")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import Foundation


/// Begrenzt Suchtreffer auf die eigene Gegend (Standort und Favoriten): Transitous sucht europaweit,
/// „Hauptbahnhof“ liefert sonst Treffer aus ganz Europa.
enum StopSearchRegion {
    static let radius: Double = 100_000  // Meter

    static func narrow(_ stops: [Stop], around anchors: [Coordinate]) -> [Stop] {
        guard !anchors.isEmpty else { return stops }
        func distance(_ stop: Stop) -> Double {
            guard let c = stop.coordinate else { return .infinity }
            return anchors.map { Geo.meters($0, c) }.min() ?? .infinity
        }
        let ranked = stops.sorted { distance($0) < distance($1) }
        let near = ranked.filter { distance($0) <= radius }
        return near.isEmpty ? stops : near
    }
}

/// Zuletzt bekannter Standort der App – für die Widget-Erweiterung, die selbst keinen Standort abfragt.
/// Auf zwei Nachkommastellen (ca. 1 km) gerundet: Für die Suche in einem Umkreis von 100 km genügt das.
enum LastLocation {
    private static let key = "lastLocation.v1"

    static func save(_ coordinate: Coordinate) {
        func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        AppGroup.defaults.set([rounded(coordinate.latitude), rounded(coordinate.longitude)], forKey: key)
    }

    static var coordinate: Coordinate? {
        guard let values = AppGroup.defaults.array(forKey: key) as? [Double], values.count == 2 else { return nil }
        return Coordinate(latitude: values[0], longitude: values[1])
    }
}

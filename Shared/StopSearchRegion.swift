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

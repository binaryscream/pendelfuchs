// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Umrechnung zwischen WGS84 und Gauß-Krüger Zone 4 (DHDN, Bessel-Ellipsoid),
/// dem Koordinatensystem der VVO-API (Mittelmeridian 12° Ost).
///
/// Transversale Mercator-Formeln nach Snyder, Datumsübergang per
/// 7-Parameter-Helmert (EPSG:1777, Position-Vector-Konvention). Genauigkeit
/// für Haltestellensuche: wenige Meter.
public enum GaussKrueger {
    public struct Point: Sendable, Hashable {
        public var easting: Double   // Rechtswert
        public var northing: Double  // Hochwert

        public init(easting: Double, northing: Double) {
            self.easting = easting
            self.northing = northing
        }
    }

    private struct Ellipsoid {
        let a: Double
        let f: Double
        var e2: Double { f * (2 - f) }
    }

    private static let bessel = Ellipsoid(a: 6_377_397.155, f: 1 / 299.1528128)
    private static let wgs84 = Ellipsoid(a: 6_378_137.0, f: 1 / 298.257223563)

    private static let zone = 4.0
    private static let centralMeridian = 12.0 * .pi / 180
    private static let falseEasting = zone * 1_000_000 + 500_000

    // DHDN → WGS84 (EPSG:1777)
    private static let tx = 598.1, ty = 73.7, tz = 418.2
    private static let rx = arcsec(0.202), ry = arcsec(0.045), rz = arcsec(-2.455)
    private static let scale = 6.7e-6

    private static func arcsec(_ s: Double) -> Double { s / 3600 * .pi / 180 }

    // MARK: Öffentliche API

    public static func toWGS84(_ p: Point) -> Coordinate {
        let (lat, lon) = inverseTM(p)
        let (x, y, z) = geodeticToECEF(lat: lat, lon: lon, ellipsoid: bessel)
        let (x2, y2, z2) = helmert(x, y, z, inverse: false)
        let (lat2, lon2) = ecefToGeodetic(x2, y2, z2, ellipsoid: wgs84)
        return Coordinate(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    public static func fromWGS84(_ c: Coordinate) -> Point {
        let (x, y, z) = geodeticToECEF(lat: c.latitude * .pi / 180, lon: c.longitude * .pi / 180, ellipsoid: wgs84)
        let (x2, y2, z2) = helmert(x, y, z, inverse: true)
        let (lat, lon) = ecefToGeodetic(x2, y2, z2, ellipsoid: bessel)
        return forwardTM(lat: lat, lon: lon)
    }

    // MARK: Transversale Mercator-Projektion (Bessel)

    private static func meridianArc(_ phi: Double, _ e2: Double, _ a: Double) -> Double {
        let e4 = e2 * e2, e6 = e4 * e2
        return a * ((1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * phi
            - (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * sin(2 * phi)
            + (15 * e4 / 256 + 45 * e6 / 1024) * sin(4 * phi)
            - (35 * e6 / 3072) * sin(6 * phi))
    }

    private static func forwardTM(lat phi: Double, lon lambda: Double) -> Point {
        let a = bessel.a, e2 = bessel.e2
        let ep2 = e2 / (1 - e2)
        let sinPhi = sin(phi), cosPhi = cos(phi), tanPhi = tan(phi)
        let n = a / sqrt(1 - e2 * sinPhi * sinPhi)
        let t = tanPhi * tanPhi
        let c = ep2 * cosPhi * cosPhi
        let aa = (lambda - centralMeridian) * cosPhi
        let m = meridianArc(phi, e2, a)

        let x = n * (aa + (1 - t + c) * pow(aa, 3) / 6
            + (5 - 18 * t + t * t + 72 * c - 58 * ep2) * pow(aa, 5) / 120)
        let y = m + n * tanPhi * (aa * aa / 2
            + (5 - t + 9 * c + 4 * c * c) * pow(aa, 4) / 24
            + (61 - 58 * t + t * t + 600 * c - 330 * ep2) * pow(aa, 6) / 720)
        return Point(easting: falseEasting + x, northing: y)
    }

    private static func inverseTM(_ p: Point) -> (lat: Double, lon: Double) {
        let a = bessel.a, e2 = bessel.e2
        let e4 = e2 * e2, e6 = e4 * e2
        let ep2 = e2 / (1 - e2)
        let x = p.easting - falseEasting
        let mu = p.northing / (a * (1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256))
        let e1 = (1 - sqrt(1 - e2)) / (1 + sqrt(1 - e2))
        let phi1 = mu
            + (3 * e1 / 2 - 27 * pow(e1, 3) / 32) * sin(2 * mu)
            + (21 * e1 * e1 / 16 - 55 * pow(e1, 4) / 32) * sin(4 * mu)
            + (151 * pow(e1, 3) / 96) * sin(6 * mu)
            + (1097 * pow(e1, 4) / 512) * sin(8 * mu)

        let sin1 = sin(phi1), cos1 = cos(phi1), tan1 = tan(phi1)
        let c1 = ep2 * cos1 * cos1
        let t1 = tan1 * tan1
        let n1 = a / sqrt(1 - e2 * sin1 * sin1)
        let r1 = a * (1 - e2) / pow(1 - e2 * sin1 * sin1, 1.5)
        let d = x / n1

        let lat = phi1 - (n1 * tan1 / r1) * (d * d / 2
            - (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * ep2) * pow(d, 4) / 24
            + (61 + 90 * t1 + 298 * c1 + 45 * t1 * t1 - 252 * ep2 - 3 * c1 * c1) * pow(d, 6) / 720)
        let lon = centralMeridian + (d - (1 + 2 * t1 + c1) * pow(d, 3) / 6
            + (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * ep2 + 24 * t1 * t1) * pow(d, 5) / 120) / cos1
        return (lat, lon)
    }

    // MARK: Datumsübergang

    private static func geodeticToECEF(lat: Double, lon: Double, ellipsoid e: Ellipsoid) -> (Double, Double, Double) {
        let n = e.a / sqrt(1 - e.e2 * sin(lat) * sin(lat))
        return (n * cos(lat) * cos(lon), n * cos(lat) * sin(lon), n * (1 - e.e2) * sin(lat))
    }

    private static func ecefToGeodetic(_ x: Double, _ y: Double, _ z: Double, ellipsoid e: Ellipsoid) -> (Double, Double) {
        let lon = atan2(y, x)
        let p = sqrt(x * x + y * y)
        var lat = atan2(z, p * (1 - e.e2))
        for _ in 0..<6 {
            let n = e.a / sqrt(1 - e.e2 * sin(lat) * sin(lat))
            lat = atan2(z + e.e2 * n * sin(lat), p)
        }
        return (lat, lon)
    }

    private static func helmert(_ x: Double, _ y: Double, _ z: Double, inverse: Bool) -> (Double, Double, Double) {
        let k: Double = inverse ? -1 : 1
        let s = 1 + k * scale
        let rx = k * rx, ry = k * ry, rz = k * rz
        var (x, y, z) = (x, y, z)
        if inverse { x -= tx; y -= ty; z -= tz }
        var xo = s * (x - rz * y + ry * z)
        var yo = s * (rz * x + y - rx * z)
        var zo = s * (-ry * x + rx * y + z)
        if !inverse { xo += tx; yo += ty; zo += tz }
        return (xo, yo, zo)
    }
}

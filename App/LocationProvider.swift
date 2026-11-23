// SPDX-License-Identifier: GPL-3.0-or-later

import CoreLocation
import FahrplanKit
import Observation

/// Ermittelt einmalig den aktuellen Standort (für „In der Nähe“).
@MainActor
@Observable
final class LocationProvider {
    enum Status: Equatable {
        case idle
        case locating
        case located(Coordinate)
        case denied
        case failed
    }

    private(set) var status: Status = .idle

    var coordinate: Coordinate? {
        if case .located(let c) = status { c } else { nil }
    }

    @ObservationIgnored private let manager = CLLocationManager()

    /// Fragt bei Bedarf die Berechtigung an und liefert den nächsten brauchbaren Standort.
    func refresh() async {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            status = .denied
            return
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }

        if coordinate == nil { status = .locating }
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }

        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    status = .denied
                    return
                }
                // Zwischengespeicherte, alte Positionen ignorieren (z. B. vom letzten Ort vor Stunden).
                if let location = update.location, location.horizontalAccuracy < 500,
                   location.timestamp.timeIntervalSinceNow > -120 {
                    status = .located(Coordinate(latitude: location.coordinate.latitude,
                                                 longitude: location.coordinate.longitude))
                    return
                }
            }
        } catch {
            status = .failed
        }
    }
}

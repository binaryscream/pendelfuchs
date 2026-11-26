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

        // Höchstens `timeout` warten: Drinnen oder mit ausgeschalteter „Genauer Position“ kommt sonst nie ein
        // brauchbarer Standort, und die Anzeige dreht sich endlos.
        rough = nil
        let search = Task { await self.locate() }
        let watchdog = Task {
            try? await Task.sleep(for: Self.timeout)
            search.cancel()
        }
        defer { watchdog.cancel() }
        let outcome = await withTaskCancellationHandler { await search.value } onCancel: { search.cancel() }

        switch outcome {
        case .found(let coordinate):
            status = .located(coordinate)
            LastLocation.save(coordinate)
        case .denied:
            status = .denied
        case .nothing:
            if Task.isCancelled {
                // Die Ansicht ist weg – nichts als Fehler melden.
                if status == .locating { status = .idle }
            } else if let rough {
                // Lieber ein ungefährer Standort als gar keiner.
                status = .located(rough)
            } else if coordinate == nil {
                status = .failed
            }
        }
    }

    private static let timeout: Duration = .seconds(12)

    private enum Outcome { case found(Coordinate), denied, nothing }

    /// Bester ungenauer Standort der laufenden Suche (Ausweichlösung nach Ablauf der Wartezeit).
    @ObservationIgnored private var rough: Coordinate?

    private func locate() async -> Outcome {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally { return .denied }
                // Zwischengespeicherte, alte Positionen ignorieren (z. B. vom letzten Ort vor Stunden).
                guard let location = update.location, location.timestamp.timeIntervalSinceNow > -120 else { continue }
                let coordinate = Coordinate(latitude: location.coordinate.latitude,
                                            longitude: location.coordinate.longitude)
                if location.horizontalAccuracy < 500 { return .found(coordinate) }
                if location.horizontalAccuracy < 5000 { rough = coordinate }
            }
        } catch {}
        return .nothing
    }
}

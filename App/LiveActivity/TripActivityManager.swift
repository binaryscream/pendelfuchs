// SPDX-License-Identifier: GPL-3.0-or-later

// ActivityKit ist noch nicht vollständig für Swift 6 annotiert (`Activity` ist nicht `Sendable`).
@preconcurrency import ActivityKit
import BackgroundTasks
import FahrplanKit
import Foundation

/// Startet, aktualisiert und beendet Live-Aktivitäten für Fahrten.
///
/// Ohne eigenen Push-Server werden Echtzeitdaten aktualisiert, wenn die App geöffnet ist
/// und im Hintergrund, wann immer iOS die App kurz aufweckt (`BGAppRefreshTask`, nicht garantiert).
/// Countdown und Fortschritt laufen in der Aktivität trotzdem live weiter.
@MainActor
final class TripActivityManager {
    static let shared = TripActivityManager()

    static let refreshTaskID = "de.fahrplanxl.app.refresh"

    private let transit: any TransitProvider = VVOProvider()

    enum StartError: LocalizedError {
        case disabled
        case noUpcomingTrip
        case notFound

        var errorDescription: String? {
            switch self {
            case .disabled:
                "Live-Aktivitäten sind für Fahrplan XL ausgeschaltet. Du kannst sie in den iPhone-Einstellungen unter Fahrplan XL aktivieren."
            case .noUpcomingTrip:
                "Für diese Fahrt steht in nächster Zeit kein Termin an."
            case .notFound:
                "Die Verbindung wurde zur gewohnten Zeit nicht gefunden – vielleicht hat sich der Fahrplan geändert."
            }
        }
    }

    private var activities: [Activity<TripActivityAttributes>] { Activity<TripActivityAttributes>.activities }

    func isRunning(_ savedID: UUID) -> Bool {
        activities.contains { $0.attributes.saved.id == savedID && $0.activityState == .active }
    }

    /// Startet die Live-Aktivität für den nächsten Termin einer Fahrt.
    /// - Parameter knownTrip: bereits geladene Verbindung (spart eine Abfrage).
    func start(_ saved: SavedTrip, knownTrip: Trip? = nil) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw StartError.disabled }

        let trip: Trip
        if let knownTrip {
            trip = knownTrip
        } else {
            guard let day = saved.upcomingDate() else { throw StartError.noUpcomingTrip }
            let found = try await transit.trips(saved.query(on: day))
            guard let match = saved.bestMatch(in: found) else { throw StartError.notFound }
            trip = match
        }

        // Pro Fahrt nur eine Aktivität.
        for activity in activities where activity.attributes.saved.id == saved.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let state = TripActivityState(trip: trip)
        _ = try Activity.request(
            attributes: TripActivityAttributes(saved: saved),
            content: content(for: state),
            pushType: nil
        )
        scheduleBackgroundRefresh()
    }

    func end(_ savedID: UUID) async {
        for activity in activities where activity.attributes.saved.id == savedID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Holt für alle laufenden Aktivitäten frische Echtzeitdaten; beendet abgeschlossene Fahrten.
    func refreshAll() async {
        let now = Date.now
        for activity in activities where activity.activityState == .active {
            let current = activity.content.state
            let saved = activity.attributes.saved

            // 10 Minuten nach Ankunft beenden, noch eine Weile auf dem Sperrbildschirm stehen lassen.
            if now > current.arrival.expectedTime.addingTimeInterval(10 * 60) {
                await activity.end(activity.content, dismissalPolicy: .after(now.addingTimeInterval(15 * 60)))
                continue
            }

            do {
                let trips = try await transit.trips(saved.query(on: current.departure.scheduledTime))
                guard let match = saved.bestMatch(in: trips) else { continue }
                await activity.update(content(for: TripActivityState(trip: match)))
            } catch {
                // Netzwerkfehler: alte Daten bleiben stehen, die Aktivität zeigt „Stand …“, sobald sie veraltet.
            }
        }
        if !activities.isEmpty { scheduleBackgroundRefresh() }
    }

    private func content(for state: TripActivityState) -> ActivityContent<TripActivityState> {
        // Nach 15 Minuten ohne Aktualisierung gelten die Daten als veraltet.
        ActivityContent(state: state, staleDate: state.updatedAt.addingTimeInterval(15 * 60),
                        relevanceScore: 100)
    }

    /// Bittet iOS, die App in ein paar Minuten kurz im Hintergrund zu wecken.
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

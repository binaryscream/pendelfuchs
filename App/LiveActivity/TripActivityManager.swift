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

    /// Bei jedem Aufruf neu, damit die Einstellung „VVO-Daten nutzen“ sofort greift.
    private var transit: any TransitProvider { DataSources.router() }

    enum StartError: LocalizedError {
        case disabled
        case noUpcomingTrip
        case notFound
        case cancelled

        var errorDescription: String? {
            switch self {
            case .disabled:
                "Live-Aktivitäten sind für Fahrplan XL ausgeschaltet. Du kannst sie in den iPhone-Einstellungen unter Fahrplan XL aktivieren."
            case .noUpcomingTrip:
                "Für diese Fahrt steht in nächster Zeit kein Termin an."
            case .notFound:
                "Die Verbindung wurde zur gewohnten Zeit nicht gefunden – vielleicht hat sich der Fahrplan geändert."
            case .cancelled:
                "Diese Verbindung ist wegen eines Ausfalls nicht fahrbar – dafür gibt es keine Live-Aktivität."
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

        var trip: Trip
        var note: String?
        if let knownTrip, knownTrip.disruption == nil {
            trip = knownTrip
        } else {
            // Nicht fahrbar oder unbekannt: frisch laden und notfalls die nächste Verbindung nehmen.
            guard let day = saved.upcomingDate() else { throw StartError.noUpcomingTrip }
            let found = try await transit.trips(saved.query(on: day))
            guard let resolved = saved.resolve(in: found) else { throw StartError.notFound }
            trip = resolved.trip
            note = resolved.note
        }

        // Pro Fahrt nur eine Aktivität.
        for activity in activities where activity.attributes.saved.id == saved.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard trip.disruption == nil else { throw StartError.cancelled }

        let state = TripActivityState(trip: trip, note: note)
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
            // Aktuelle Einstellungen der gemerkten Fahrt (z. B. Verpass-Assistent), falls sie noch gespeichert ist.
            let saved = SavedTripsStore(defaults: AppGroup.defaults).trip(id: activity.attributes.saved.id)
                ?? activity.attributes.saved

            // 5 Minuten nach der Ankunft beenden (und kurz darauf vom Sperrbildschirm nehmen).
            if now > current.arrival.expectedTime.addingTimeInterval(5 * 60) {
                await activity.end(activity.content, dismissalPolicy: .after(now.addingTimeInterval(5 * 60)))
                continue
            }

            do {
                let trips = try await transit.trips(saved.query(on: current.departure.scheduledTime))
                guard let resolved = saved.resolve(in: trips) else { continue }
                await activity.update(content(for: TripActivityState(trip: resolved.trip, note: resolved.note)))
            } catch {
                // Netzwerkfehler: alte Daten bleiben stehen, die Aktivität zeigt „Stand …“, sobald sie veraltet.
            }
        }
        if !activities.isEmpty { scheduleBackgroundRefresh() }
    }

    /// Hintergrundabfrage für Live-Aktivitäten und Benachrichtigungen: alles aktualisieren, dann neu planen.
    func backgroundRefresh() async {
        await refreshAll()
        await TripNotifier.shared.checkAll()
        scheduleBackgroundRefresh()
    }

    /// Nächster Phasenwechsel aller laufenden Aktivitäten – dann soll iOS die App möglichst wecken.
    private var nextChange: Date? {
        activities.compactMap { $0.content.state.nextChange(after: .now) }.min()
    }

    private func content(for state: TripActivityState) -> ActivityContent<TripActivityState> {
        // „Veraltet“ spätestens nach 15 Minuten – oder schon beim nächsten Phasenwechsel (Abfahrt, Ankunft,
        // Umstieg): Dann zeichnet iOS die Aktivität neu, und sie zeigt die neue Phase auch ohne geöffnete App.
        let fifteen = state.updatedAt.addingTimeInterval(15 * 60)
        let next = state.nextChange(after: .now).map { $0.addingTimeInterval(1) } ?? fifteen
        return ActivityContent(state: state, staleDate: min(fifteen, next), relevanceScore: 100)
    }

    /// Bittet iOS, die App bald kurz im Hintergrund zu wecken – für laufende Live-Aktivitäten und für
    /// Benachrichtigungen zu anstehenden Fahrten. iOS entscheidet selbst, ob und wann.
    func scheduleBackgroundRefresh() {
        var wanted: [Date] = []
        // Live-Aktivität: zum nächsten Phasenwechsel, höchstens 5 Minuten warten.
        if !activities.isEmpty {
            wanted.append(min(nextChange ?? .now.addingTimeInterval(5 * 60), .now.addingTimeInterval(5 * 60)))
        }
        if let check = TripNotifier.shared.nextCheck() { wanted.append(check) }
        guard let earliest = wanted.min() else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = max(earliest, .now.addingTimeInterval(60))
        try? BGTaskScheduler.shared.submit(request)
    }
}

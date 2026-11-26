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

    /// Aktivitäten, die noch zu sehen sind und aktualisiert werden können. Dazu gehört auch `.stale`: So heißt
    /// eine laufende Aktivität, sobald ihr `staleDate` vorbei ist – und das setzen wir bewusst auf den nächsten
    /// Phasenwechsel. Wer nur `.active` prüft, aktualisiert sie danach nie wieder.
    static var running: [Activity<TripActivityAttributes>] {
        Activity<TripActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    func isRunning(_ savedID: UUID) -> Bool {
        Self.running.contains { $0.attributes.saved.id == savedID }
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

        // Erst prüfen, dann die alte Aktivität beenden – sonst verschwindet sie, ohne dass eine neue kommt.
        guard trip.disruption == nil else { throw StartError.cancelled }

        // Pro Fahrt nur eine Aktivität.
        for activity in activities where activity.attributes.saved.id == saved.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

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

    /// Beendet alle laufenden Aktivitäten; liefert, wie viele es waren.
    @discardableResult
    func endAll() async -> Int {
        let running = Self.running
        for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
        return running.count
    }

    /// Holt für alle laufenden Aktivitäten frische Echtzeitdaten; beendet abgeschlossene Fahrten.
    func refreshAll() async {
        let now = Date.now
        for activity in Self.running {
            let current = activity.content.state
            // Aktuelle Einstellungen der gemerkten Fahrt (z. B. Verpass-Assistent), falls sie noch gespeichert ist.
            let saved = SavedTripsStore(defaults: AppGroup.defaults).trip(id: activity.attributes.saved.id)
                ?? activity.attributes.saved

            // Erst frische Daten holen: Die alte Ankunftszeit kann durch eine neue Verspätung überholt sein.
            var state = current
            var isFresh = false
            if let trips = try? await transit.trips(saved.query(on: current.departure.scheduledTime)),
               let resolved = saved.resolve(in: trips) {
                state = TripActivityState(trip: resolved.trip, note: resolved.note)
                isFresh = true
            }

            // 5 Minuten nach der Ankunft beenden (und kurz darauf vom Sperrbildschirm nehmen). Ohne frische
            // Daten großzügiger, damit eine unbemerkte Verspätung die Aktivität nicht unterwegs beendet.
            let reserve: TimeInterval = isFresh ? 5 * 60 : 30 * 60
            if now > state.arrival.expectedTime.addingTimeInterval(reserve) {
                await activity.end(content(for: state), dismissalPolicy: .after(now.addingTimeInterval(5 * 60)))
                continue
            }
            // Auch ohne neue Daten (kein Netz, Verbindung nicht gefunden) neu setzen: iOS zeichnet die Aktivität
            // dann in der aktuellen Phase und bekommt den Zeitpunkt des nächsten Phasenwechsels. „Stand …“ zeigt
            // weiter die Zeit der letzten erfolgreichen Abfrage.
            await activity.update(content(for: state))
        }
        if !Self.running.isEmpty { scheduleBackgroundRefresh() }
    }

    /// Hintergrundabfrage für Live-Aktivitäten und Benachrichtigungen: alles aktualisieren, dann neu planen.
    func backgroundRefresh() async {
        await refreshAll()
        await TripNotifier.shared.checkAll()
        await TripNotifier.shared.scheduleReminders()
        scheduleBackgroundRefresh()
    }

    /// Nächster Phasenwechsel aller laufenden Aktivitäten – dann soll iOS die App möglichst wecken.
    private var nextChange: Date? {
        Self.running.compactMap { $0.content.state.nextChange(after: .now) }.min()
    }

    private func content(for state: TripActivityState) -> ActivityContent<TripActivityState> {
        // „Veraltet“ spätestens nach 15 Minuten – oder schon beim nächsten Phasenwechsel (Abfahrt, Ankunft,
        // Umstieg): Dann zeichnet iOS die Aktivität neu, und sie zeigt die neue Phase auch ohne geöffnete App.
        let fifteen = Date.now.addingTimeInterval(15 * 60)
        let next = state.nextChange(after: .now).map { $0.addingTimeInterval(1) } ?? fifteen
        return ActivityContent(state: state, staleDate: min(fifteen, next), relevanceScore: 100)
    }

    /// Bittet iOS, die App bald kurz im Hintergrund zu wecken – für laufende Live-Aktivitäten und für
    /// Benachrichtigungen zu anstehenden Fahrten. iOS entscheidet selbst, ob und wann.
    func scheduleBackgroundRefresh() {
        var wanted: [Date] = []
        // Live-Aktivität: zum nächsten Phasenwechsel, höchstens 5 Minuten warten.
        if !Self.running.isEmpty {
            wanted.append(min(nextChange ?? .now.addingTimeInterval(5 * 60), .now.addingTimeInterval(5 * 60)))
        }
        if let check = TripNotifier.shared.nextCheck() { wanted.append(check) }
        guard let earliest = wanted.min() else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = max(earliest, .now.addingTimeInterval(60))
        try? BGTaskScheduler.shared.submit(request)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

// ActivityKit ist noch nicht vollständig für Swift 6 annotiert.
@preconcurrency import ActivityKit
import FahrplanKit
import Foundation
import UserNotifications

/// Prüft gemerkte Fahrten und benachrichtigt bei Ausfall, Verspätung, Gleiswechsel und Anschlussproblemen.
///
/// Ohne eigenen Push-Server sind das lokale Benachrichtigungen: Geprüft wird, solange die App offen ist (jede
/// Minute) und im Hintergrund, wann immer iOS die App kurz weckt – das ist nicht garantiert und oft nur alle
/// 15 Minuten oder seltener.
@MainActor
final class TripNotifier {
    static let shared = TripNotifier()

    /// Wie lange vor der Abfahrt eine Fahrt beobachtet wird.
    static let leadTime: TimeInterval = 60 * 60

    private var transit: any TransitProvider { DataSources.router() }
    private let center = UNUserNotificationCenter.current()
    private var isChecking = false

    // MARK: Einstellungen

    static let enabledKey = "notifications.enabled"
    static let delayThresholdKey = "notifications.delayThreshold"
    static func kindKey(_ kind: TripNoticeKind) -> String { "notifications.kind.\(kind.rawValue)" }

    private var defaults: UserDefaults { AppGroup.defaults }

    var isEnabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }

    var settings: TripWatchSettings {
        let kinds = TripNoticeKind.allCases.filter { defaults.object(forKey: Self.kindKey($0)) as? Bool ?? true }
        let threshold = defaults.object(forKey: Self.delayThresholdKey) as? Int ?? 5
        return TripWatchSettings(enabledKinds: Set(kinds), delayThreshold: threshold)
    }

    // MARK: Erinnerung vor der Abfahrt

    static let reminderKey = "notifications.reminder"
    static let reminderLeadKey = "notifications.reminderLead"
    /// Kategorie der Erinnerung – bringt den Knopf „Live-Aktivität starten“ mit.
    static let startCategory = "TRIP_START"
    nonisolated static let startActionID = "START_LIVE"

    var remindersEnabled: Bool { isEnabled && (defaults.object(forKey: Self.reminderKey) as? Bool ?? true) }
    /// So viele Minuten vor der Abfahrt kommt die Erinnerung.
    var reminderLead: Int { defaults.object(forKey: Self.reminderLeadKey) as? Int ?? 20 }

    /// Meldet iOS den Knopf unter der Erinnerung an (einmal beim Start der App).
    static func registerCategories() {
        // `.foreground`: Der Knopf öffnet die App – eine Live-Aktivität darf iOS nur von dort aus starten lassen.
        let start = UNNotificationAction(identifier: startActionID, title: "Live-Aktivität starten",
                                         options: [.foreground])
        let category = UNNotificationCategory(identifier: startCategory, actions: [start], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private static let reminderPrefix = "start|"

    private func reminderID(_ saved: SavedTrip, departure: Date) -> String {
        "\(Self.reminderPrefix)\(saved.id.uuidString)|\(Int(departure.timeIntervalSince1970))"
    }

    /// Plant die Erinnerungen der nächsten Termine fest ein. Anders als die Echtzeit-Meldungen kommen sie
    /// deshalb auch dann pünktlich, wenn iOS die App im Hintergrund nicht weckt.
    func scheduleReminders(now: Date = .now) async {
        let old = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(Self.reminderPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        guard remindersEnabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let lead = reminderLead
        let time = Date.FormatStyle.dateTime.hour().minute()
        var planned = 0
        for saved in SavedTripsStore(defaults: defaults).trips where saved.isRegular && saved.usesNotifications {
            // Die nächsten fünf Termine je Fahrt (iOS erlaubt insgesamt nur 64 geplante Meldungen).
            var cursor = now
            for _ in 0..<5 {
                guard planned < 50, let departure = saved.nextOccurrence(after: cursor, grace: 0) else { break }
                cursor = departure.addingTimeInterval(60)
                let fire = departure.addingTimeInterval(TimeInterval(-lead * 60))
                guard fire > now.addingTimeInterval(5) else { continue }

                let content = UNMutableNotificationContent()
                content.title = saved.title
                let line = saved.lines.first.map { " mit \($0)" } ?? ""
                content.body = "In \(lead) Minuten: Abfahrt \(departure.formatted(time))\(line) ab \(saved.origin.label(.current))."
                content.sound = .default
                content.threadIdentifier = saved.id.uuidString
                content.categoryIdentifier = Self.startCategory
                content.userInfo = [NotificationRouter.savedTripKey: saved.id.uuidString]
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: reminderID(saved, departure: departure),
                                                            content: content, trigger: trigger))
                planned += 1
            }
        }
    }

    /// Knopf „Live-Aktivität starten“ unter der Erinnerung. Die App kommt dabei gerade erst in den Vordergrund,
    /// deshalb ein paar Versuche: Vorher lehnt iOS den Start ab.
    func startActivity(forSavedTrip id: UUID) async {
        guard let saved = SavedTripsStore(defaults: defaults).trip(id: id) else { return }
        for attempt in 0..<4 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            do {
                try await TripActivityManager.shared.start(saved)
                return
            } catch let error as TripActivityManager.StartError {
                // Fachliche Gründe (keine Fahrt, Ausfall, ausgeschaltet) ändern sich durch Warten nicht.
                _ = error
                return
            } catch {
                continue
            }
        }
    }

    // MARK: Prüfen

    /// Fragt einmalig nach der Erlaubnis (nur aus der geöffneten App heraus sinnvoll).
    func requestAuthorizationIfNeeded() async {
        guard isEnabled, !watchedTrips(now: .now, horizon: 7 * 24 * 3600).isEmpty else { return }
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// Prüft alle Fahrten, die gerade anstehen oder unterwegs sind, und verschickt neue Meldungen.
    func checkAll(now: Date = .now) async {
        guard isEnabled, !isChecking else { return }
        // Vor dem ersten `await` setzen – sonst kommen zwei gleichzeitige Aufrufe beide durch und melden doppelt.
        isChecking = true
        defer { isChecking = false }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let settings = settings
        var memories = loadMemories(now: now)
        for (saved, day) in watchedTrips(now: now, horizon: Self.leadTime) {
            // Sparsam: nach der ersten Suche des Tages nur noch diese eine Verbindung abholen.
            guard let lookup = try? await SavedTripLookup.lookup(saved, on: day, now: now, using: transit,
                                                                 suite: AppGroup.id),
                  let match = lookup.match else { continue }
            let resolved = lookup.resolved
            let replacement = resolved?.note != nil ? resolved?.trip : nil
            let key = memoryKey(saved, day: day)
            let result = TripWatch.notices(for: match, replacement: replacement, title: saved.title, now: now,
                                           memory: memories[key] ?? TripWatchMemory(), settings: settings)
            memories[key] = result.memory
            for notice in result.notices { await send(notice, about: saved) }
            // Fällt die Fahrt ersatzlos aus, braucht es keine Erinnerung an die Abfahrt mehr.
            if replacement == nil, let disruption = match.disruption, disruption.preventsBoarding {
                center.removePendingNotificationRequests(withIdentifiers: [reminderID(saved, departure: day)])
            }
        }
        saveMemories(memories)
    }

    /// Wann die nächste Prüfung im Hintergrund sinnvoll ist (Beginn des nächsten Beobachtungsfensters oder,
    /// wenn eins läuft, bald); `nil`, wenn keine Fahrt beobachtet wird. Bewusst ohne Obergrenze: Sonst plant
    /// die App am Freitagabend nichts mehr und verschläft den Montag.
    func nextCheck(now: Date = .now) -> Date? {
        guard isEnabled else { return nil }
        if !watchedTrips(now: now, horizon: Self.leadTime).isEmpty { return now.addingTimeInterval(5 * 60) }
        let starts = watchedTrips(now: now, horizon: 8 * 24 * 3600).map { $0.day.addingTimeInterval(-Self.leadTime) }
        return starts.min()
    }

    /// Regelmäßige Fahrten (und Fahrten mit laufender Live-Aktivität), deren Abfahrt höchstens `horizon` entfernt
    /// ist oder die gerade unterwegs sind – mit dem Abfahrtszeitpunkt des Termins.
    private func watchedTrips(now: Date, horizon: TimeInterval) -> [(saved: SavedTrip, day: Date)] {
        var seen = Set<UUID>()
        var result: [(SavedTrip, Date)] = []
        let store = SavedTripsStore(defaults: defaults)

        // Beobachtet bis zur geplanten Ankunft (falls bekannt) plus Reserve für Verspätungen.
        func span(_ saved: SavedTrip) -> TimeInterval {
            let duration = saved.arrival.map { arrival -> TimeInterval in
                let minutes = (arrival.minutesSinceMidnight - saved.departure.minutesSinceMidnight + 24 * 60) % (24 * 60)
                return TimeInterval(minutes * 60)
            } ?? 90 * 60
            return duration + 30 * 60
        }

        func consider(_ saved: SavedTrip, departure: Date) {
            guard !seen.contains(saved.id) else { return }
            let end = departure.addingTimeInterval(span(saved))
            guard departure.timeIntervalSince(now) <= horizon, end > now else { return }
            seen.insert(saved.id)
            result.append((saved, departure))
        }

        for saved in store.trips where saved.isRegular && saved.usesNotifications {
            // Der laufende Termin zählt genau so lange, wie er beobachtet wird – danach ist der nächste dran.
            if let next = saved.nextOccurrence(after: now, grace: span(saved)) { consider(saved, departure: next) }
        }
        for activity in TripActivityManager.running {
            let saved = store.trip(id: activity.attributes.saved.id) ?? activity.attributes.saved
            guard saved.usesNotifications else { continue }
            consider(saved, departure: activity.content.state.departure.scheduledTime)
        }
        return result
    }

    private func send(_ notice: TripNotice, about saved: SavedTrip) async {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.threadIdentifier = saved.id.uuidString
        // Ausfall und Anschlussproblem dulden keinen Aufschub: als dringliche Meldung markiert, die einen Fokus
        // durchbricht (Berechtigung in `project.yml`, nur mit bezahltem Entwicklerkonto).
        if notice.kind == .cancellation || notice.kind == .connection { content.interruptionLevel = .timeSensitive }
        // Antippen öffnet die Fahrt (siehe `NotificationPresenter`).
        content.userInfo = [NotificationRouter.savedTripKey: saved.id.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Vergisst, was schon gemeldet wurde (für „Daten zurücksetzen“).
    func forgetMemories() { defaults.removeObject(forKey: memoryStorageKey) }

    // MARK: Gedächtnis (was schon gemeldet wurde)

    private let memoryStorageKey = "notifications.memory.v1"

    private func memoryKey(_ saved: SavedTrip, day: Date) -> String {
        "\(saved.id.uuidString)|\(Int(day.timeIntervalSince1970))"
    }

    private func loadMemories(now: Date) -> [String: TripWatchMemory] {
        guard let data = defaults.data(forKey: memoryStorageKey),
              let all = try? JSONDecoder().decode([String: TripWatchMemory].self, from: data) else { return [:] }
        // Einträge älter als zwei Tage brauchen wir nicht mehr.
        return all.filter { key, _ in
            guard let seconds = key.split(separator: "|").last.flatMap({ Double($0) }) else { return false }
            return now.timeIntervalSince1970 - seconds < 2 * 24 * 3600
        }
    }

    private func saveMemories(_ memories: [String: TripWatchMemory]) {
        if let data = try? JSONEncoder().encode(memories) { defaults.set(data, forKey: memoryStorageKey) }
    }
}

/// Zeigt Benachrichtigungen auch an, während die App offen ist, und öffnet beim Antippen die Fahrt.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // Bewusst die Variante mit Rückruf statt `async`: Die `async`-Fassung meldet sich von einem beliebigen Thread
    // zurück, und iOS bricht die App dann mit „Call must be made on main thread“ ab. iOS ruft hier auf dem
    // Hauptthread an – die Rückmeldung geht sofort von dort zurück, die Arbeit läuft danach.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let text = response.notification.request.content.userInfo[NotificationRouter.savedTripKey] as? String
        let startsActivity = response.actionIdentifier == TripNotifier.startActionID
        if let id = text.flatMap(UUID.init(uuidString:)) {
            Task { @MainActor in
                NotificationRouter.shared.savedTripToOpen = id
                if startsActivity { await TripNotifier.shared.startActivity(forSavedTrip: id) }
            }
        }
        completionHandler()
    }
}

/// Welche gemerkte Fahrt nach dem Antippen einer Benachrichtigung geöffnet werden soll.
@MainActor @Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    nonisolated static let savedTripKey = "savedTripID"

    var savedTripToOpen: UUID?
}

private extension TripDisruption {
    /// Die Fahrt lässt sich gar nicht antreten (statt nur: Anschluss oder Ausstieg betroffen).
    var preventsBoarding: Bool {
        switch self {
        case .rideCancelled, .boardingCancelled: true
        case .alightingCancelled, .connectionMissed: false
        }
    }
}

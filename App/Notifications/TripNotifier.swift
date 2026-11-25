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
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        isChecking = true
        defer { isChecking = false }

        let settings = settings
        var memories = loadMemories(now: now)
        for (saved, day) in watchedTrips(now: now, horizon: Self.leadTime) {
            guard let trips = try? await transit.trips(saved.query(on: day)),
                  let match = saved.bestMatch(in: trips) else { continue }
            let resolved = saved.resolve(in: trips, now: now)
            let replacement = resolved?.note != nil ? resolved?.trip : nil
            let key = memoryKey(saved, day: day)
            let result = TripWatch.notices(for: match, replacement: replacement, title: saved.title, now: now,
                                           memory: memories[key] ?? TripWatchMemory(), settings: settings)
            memories[key] = result.memory
            for notice in result.notices { await send(notice, about: saved) }
        }
        saveMemories(memories)
    }

    /// Wann die nächste Prüfung im Hintergrund sinnvoll ist (Beginn des nächsten Beobachtungsfensters oder,
    /// wenn eins läuft, bald); `nil`, wenn in den nächsten 24 Stunden nichts ansteht.
    func nextCheck(now: Date = .now) -> Date? {
        guard isEnabled else { return nil }
        if !watchedTrips(now: now, horizon: Self.leadTime).isEmpty { return now.addingTimeInterval(5 * 60) }
        let starts = watchedTrips(now: now, horizon: 24 * 3600).map { $0.day.addingTimeInterval(-Self.leadTime) }
        return starts.min()
    }

    /// Regelmäßige Fahrten (und Fahrten mit laufender Live-Aktivität), deren Abfahrt höchstens `horizon` entfernt
    /// ist oder die gerade unterwegs sind – mit dem Abfahrtszeitpunkt des Termins.
    private func watchedTrips(now: Date, horizon: TimeInterval) -> [(saved: SavedTrip, day: Date)] {
        var seen = Set<UUID>()
        var result: [(SavedTrip, Date)] = []
        let store = SavedTripsStore(defaults: defaults)

        func consider(_ saved: SavedTrip, departure: Date) {
            guard !seen.contains(saved.id) else { return }
            // Ende: geplante Ankunft (falls bekannt) plus Reserve für Verspätungen.
            let duration = saved.arrival.map { arrival -> TimeInterval in
                let minutes = (arrival.minutesSinceMidnight - saved.departure.minutesSinceMidnight + 24 * 60) % (24 * 60)
                return TimeInterval(minutes * 60)
            } ?? 90 * 60
            let end = departure.addingTimeInterval(duration + 30 * 60)
            guard departure.timeIntervalSince(now) <= horizon, end > now else { return }
            seen.insert(saved.id)
            result.append((saved, departure))
        }

        for saved in store.trips where saved.isRegular {
            if let next = saved.nextOccurrence(after: now, grace: 3 * 3600) { consider(saved, departure: next) }
        }
        for activity in Activity<TripActivityAttributes>.activities where activity.activityState == .active {
            let saved = store.trip(id: activity.attributes.saved.id) ?? activity.attributes.saved
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
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

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

/// Zeigt Benachrichtigungen auch an, während die App offen ist.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

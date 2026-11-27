// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI
import UserNotifications

/// Einstellungen: worüber die App zu regelmäßigen Fahrten benachrichtigt.
struct NotificationSettingsView: View {
    @AppStorage(TripNotifier.enabledKey, store: AppGroup.defaults) private var enabled = true
    @AppStorage(TripNotifier.delayThresholdKey, store: AppGroup.defaults) private var delayThreshold = 5
    @AppStorage(TripNotifier.kindKey(.cancellation), store: AppGroup.defaults) private var cancellation = true
    @AppStorage(TripNotifier.kindKey(.delay), store: AppGroup.defaults) private var delay = true
    @AppStorage(TripNotifier.kindKey(.platformChange), store: AppGroup.defaults) private var platformChange = true
    @AppStorage(TripNotifier.kindKey(.connection), store: AppGroup.defaults) private var connection = true

    @AppStorage(TripNotifier.reminderKey, store: AppGroup.defaults) private var reminder = true
    @AppStorage(TripNotifier.reminderLeadKey, store: AppGroup.defaults) private var reminderLead = 20
    @AppStorage(TripNotifier.urgentKey, store: AppGroup.defaults) private var urgent = true

    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus?
    /// Schalter „Dringliche Mitteilungen“ in den iPhone-Einstellungen (nur lesbar).
    @State private var timeSensitive: UNNotificationSetting?
    /// Welcher Testknopf gerade wartet (für die Beschriftung); solange sind alle gesperrt.
    @State private var pendingTest: TestKind?
    @State private var testError: String?

    private enum TestKind { case plain, reminder, urgent }

    var body: some View {
        Form {
            Section {
                Toggle("Benachrichtigungen", isOn: $enabled)
                if enabled, status == .notDetermined {
                    Button("Benachrichtigungen erlauben") { Task { await requestAuthorization() } }
                }
                if enabled, status == .denied {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("In den iPhone-Einstellungen ausgeschaltet", systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                        Button("iPhone-Einstellungen öffnen") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            } footer: {
                Text("Für regelmäßige Fahrten aus „Meine Fahrten“ und Fahrten mit laufender Live-Aktivität – ab einer Stunde vor der Abfahrt bis zur Ankunft. Einzelne Fahrten lassen sich in ihren Einstellungen ausnehmen.")
            }

            if enabled {
                Section {
                    Toggle("Ausfall", isOn: $cancellation)
                    Toggle("Verspätung", isOn: $delay)
                    if delay {
                        Picker("Ab", selection: $delayThreshold) {
                            ForEach([3, 5, 10, 15], id: \.self) { Text("\($0) Minuten").tag($0) }
                        }
                    }
                    Toggle("Gleis- und Steigwechsel", isOn: $platformChange)
                    Toggle("Anschluss verpasst oder knapp", isOn: $connection)
                } header: {
                    Text("Benachrichtigen bei")
                } footer: {
                    Text("Ohne eigenen Server prüft die App selbst: jede Minute, solange sie offen ist, und im Hintergrund, wenn iOS sie kurz weckt. Das ist nicht garantiert und oft nur etwa alle 15 Minuten – eine Meldung kann also später kommen.")
                }

                if cancellation || connection {
                    Section {
                        Toggle("Dringlich: Ausfall und Anschluss", isOn: $urgent)
                        if urgent, timeSensitive == .disabled {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("In den iPhone-Einstellungen sind dringliche Mitteilungen aus",
                                      systemImage: "exclamationmark.circle")
                                    .foregroundStyle(.orange)
                                Button("iPhone-Einstellungen öffnen") {
                                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            }
                        }
                    } footer: {
                        Text("Kommt auch durch einen Fokus wie „Nicht stören“ oder „Schlafen“. Gilt nur für Ausfälle und verpasste oder knappe Anschlüsse – Verspätungen und Gleiswechsel bleiben normale Meldungen.")
                    }
                }

                Section {
                    Toggle("Erinnerung vor der Abfahrt", isOn: $reminder)
                    if reminder {
                        Picker("Vorlauf", selection: $reminderLead) {
                            ForEach([10, 15, 20, 30, 45], id: \.self) { Text("\($0) Minuten").tag($0) }
                        }
                    }
                } header: {
                    Text("Vor der Abfahrt")
                } footer: {
                    Text("Für regelmäßige Fahrten, mit dem Knopf „Live-Aktivität starten“ (Meldung gedrückt halten). Die Erinnerung ist fest eingeplant und kommt pünktlich – sie richtet sich nach dem Fahrplan, nicht nach einer Verspätung.")
                }

                Section {
                    testButton(.plain, "Testbenachrichtigung senden", icon: "bell.and.waves.left.and.right")
                    if reminder {
                        testButton(.reminder, "Test: Erinnerung mit Startknopf", icon: "livephoto")
                    }
                    if urgent, cancellation || connection {
                        testButton(.urgent, "Test: dringliche Meldung", icon: "exclamationmark.bubble")
                    }
                } footer: {
                    if let testError {
                        Text(testError).foregroundStyle(.red)
                    } else {
                        Text("Kommt nach 5 Sekunden – so bleibt Zeit, das iPhone zu sperren oder die App zu verlassen. Für die dringliche Meldung vorher einen Fokus wie „Nicht stören“ einschalten: Sie sollte trotzdem erscheinen.")
                    }
                }
            }
        }
        .navigationTitle("Benachrichtigungen")
        .task(id: scenePhase) {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            status = settings.authorizationStatus
            timeSensitive = settings.timeSensitiveSetting
        }
        .onChange(of: enabled) { _, isOn in
            Task {
                if isOn { await requestAuthorization() }
                await TripNotifier.shared.scheduleReminders()
            }
        }
        .onChange(of: reminder) { Task { await TripNotifier.shared.scheduleReminders() } }
        .onChange(of: reminderLead) { Task { await TripNotifier.shared.scheduleReminders() } }
    }

    private func testButton(_ kind: TestKind, _ title: String, icon: String) -> some View {
        Button {
            Task { await sendTest(kind) }
        } label: {
            Label(pendingTest == kind ? "Kommt in 5 Sekunden …" : title,
                  systemImage: pendingTest == kind ? "checkmark.circle" : icon)
        }
        .disabled(pendingTest != nil || status == .denied)
    }

    /// Beispielmeldung, wie sie bei einer Verspätung käme – nach 5 Sekunden.
    private func sendTest(_ kind: TestKind) async {
        let center = UNUserNotificationCenter.current()
        if status != .authorized && status != .provisional && status != .ephemeral {
            await requestAuthorization()
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        }
        let content = UNMutableNotificationContent()
        content.title = "Test: Zur Arbeit"
        content.body = "So sieht eine Meldung aus – z. B. „Abfahrt S1 +6 min, jetzt 7:42.“"
        content.sound = .default
        // Wie echte Meldungen: Antippen öffnet die erste regelmäßige Fahrt, falls es eine gibt.
        if let saved = SavedTripsStore(defaults: AppGroup.defaults).regular().first {
            content.title = "Test: \(saved.title)"
            content.userInfo = [NotificationRouter.savedTripKey: saved.id.uuidString]
        }
        switch kind {
        case .plain: break
        case .reminder:
            // Wie die echte Erinnerung: mit dem Knopf „Live-Aktivität starten“.
            content.body = "In \(reminderLead) Minuten: Abfahrt. Gedrückt halten für „Live-Aktivität starten“."
            content.categoryIdentifier = TripNotifier.startCategory
        case .urgent:
            // Wie ein echter Ausfall: dringlich, kommt auch durch einen Fokus.
            content.body = "So sieht eine dringliche Meldung aus – z. B. „S1 7:36 fällt aus.“ Sie kommt auch durch einen Fokus."
            content.interruptionLevel = .timeSensitive
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content,
                                                       trigger: trigger))
            testError = nil
        } catch {
            testError = "Die Testmeldung konnte nicht geplant werden: \(error.localizedDescription)"
            return
        }
        pendingTest = kind
        try? await Task.sleep(for: .seconds(6))
        pendingTest = nil
    }

    private func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        let settings = await center.notificationSettings()
        status = settings.authorizationStatus
        timeSensitive = settings.timeSensitiveSetting
    }
}

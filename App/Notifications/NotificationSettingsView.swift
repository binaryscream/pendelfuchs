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

    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus?

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
                Text("Für regelmäßige Fahrten aus „Meine Fahrten“ und Fahrten mit laufender Live-Aktivität – ab einer Stunde vor der Abfahrt bis zur Ankunft.")
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
            }
        }
        .navigationTitle("Benachrichtigungen")
        .task(id: scenePhase) { status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .onChange(of: enabled) { _, isOn in
            if isOn { Task { await requestAuthorization() } }
        }
    }

    private func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        status = await center.notificationSettings().authorizationStatus
    }
}

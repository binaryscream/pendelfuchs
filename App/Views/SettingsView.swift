// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Erscheinungsbild der App, unabhängig von der Systemeinstellung wählbar.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// `nil` = dem System folgen.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static let storageKey = "appearance"
}

struct SettingsView: View {
    @AppStorage(DataSources.useVVOKey, store: AppGroup.defaults) private var useVVO = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Benachrichtigungen", systemImage: "bell.badge")
                    }
                    NavigationLink {
                        DisplaySettingsView()
                    } label: {
                        Label("Anzeige", systemImage: "textformat.size")
                    }
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Datenschutz & Daten", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        FAQView()
                    } label: {
                        Label("Hilfe & Fragen", systemImage: "questionmark.circle")
                    }
                } footer: {
                    Text("Unter „Anzeige“: Start-Tab, Erscheinungsbild, Haltestellennamen, Verspätungen, Störungen, Ausfälle und Zwischenhalte.")
                }

                Section {
                    Toggle("VVO-Daten im VVO-Gebiet", isOn: $useVVO)
                } header: {
                    Text("Datenquellen")
                } footer: {
                    Text("Fahrplandaten für ganz Deutschland kommen von Transitous. Im Gebiet des Verkehrsverbunds Oberelbe (Dresden, Meißen, Pirna, Bautzen …) kann die App zusätzlich die Daten des VVO nutzen – mit Fahrpreisen und Auslastung.")
                }

                Section {
                    Link(destination: DataSources.transitousSourcesURL) {
                        LabeledContent("Transitous", value: "Quellen und Lizenzen")
                    }
                    Link(destination: DataSources.openStreetMapURL) {
                        LabeledContent("Kartendaten", value: "© OpenStreetMap-Mitwirkende")
                    }
                    Link(destination: URL(string: "https://openfreemap.org")!) {
                        LabeledContent("Kartenkacheln", value: "OpenFreeMap, © OpenMapTiles")
                    }
                    Link(destination: URL(string: "https://maplibre.org")!) {
                        LabeledContent("Kartendarstellung", value: "MapLibre (BSD-Lizenz)")
                    }
                    Link(destination: URL(string: "https://tlm.solutions")!) {
                        LabeledContent("Live-Fahrzeuge Dresden", value: "TLMS")
                    }
                    if useVVO {
                        LabeledContent("VVO-Gebiet", value: "Verkehrsverbund Oberelbe")
                    }
                } header: {
                    Text("Quellenangaben")
                } footer: {
                    Text("Fahrplandaten u. a. von DELFI e. V. (opendata-oepnv.de, CC BY 4.0), bereitgestellt über Transitous.")
                }

                Section("Über") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    LabeledContent("Lizenz", value: "GPL-3.0")
                    LabeledContent("Kontakt", value: AppInfo.responsibleName)
                    if let mail = AppInfo.contactURL {
                        Link(destination: mail) {
                            LabeledContent("E-Mail", value: AppInfo.contactEmail ?? "")
                        }
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }
}

/// Alles, was nur das Aussehen betrifft – gebündelt, damit die Einstellungen kurz bleiben.
struct DisplaySettingsView: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system
    @AppStorage(DelayDisplay.storageKey, store: AppGroup.defaults) private var delayDisplay = DelayDisplay.badge
    @AppStorage(StopNameStyle.storageKey, store: AppGroup.defaults) private var stopNameStyle = StopNameStyle.withPlace
    @AppStorage(StopListExpansion.storageKey) private var stopListExpansion = StopListExpansion.collapsed
    @AppStorage(CancelledDisplay.hideKey, store: AppGroup.defaults) private var hideCancelled = false
    @AppStorage(AlertDisplay.storageKey, store: AppGroup.defaults) private var alertDisplay = AlertDisplay.affected
    @AppStorage(AppTab.startKey) private var startTab = AppTab.departures

    var body: some View {
        Form {
            Section {
                Picker("Beim Start öffnen", selection: $startTab) {
                    ForEach(AppTab.startChoices, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Dieser Bereich erscheint, wenn du die App neu öffnest. Widgets und Benachrichtigungen führen weiterhin direkt zu ihrem Ziel.")
            }

            Section {
                Picker("Erscheinungsbild", selection: $appearance) {
                    ForEach(AppearanceSetting.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Erscheinungsbild")
            } footer: {
                Text("„System“ folgt der Einstellung deines iPhones und wechselt z. B. abends automatisch in den Dunkelmodus.")
            }

            Section {
                Picker("Haltestellennamen", selection: $stopNameStyle) {
                    ForEach(StopNameStyle.allCases) { option in
                        VStack(alignment: .leading) {
                            Text(option.title)
                            Text(option.example).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Haltestellennamen anzeigen")
            } footer: {
                Text("„Mit Ort“ setzt den Ort davor, damit „Hbf“ und „Bahnhof“ eindeutig sind. Gilt in der ganzen App, im Widget und in der Live-Aktivität.")
            }

            Section {
                Picker("Verspätungen", selection: $delayDisplay) {
                    ForEach(DelayDisplay.allCases) { option in
                        VStack(alignment: .leading) {
                            Text(option.title)
                            Text(option.example).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Verspätungen anzeigen")
            } footer: {
                Text("Gilt in der ganzen App, im Widget und in der Live-Aktivität. Die Minuten bis zur Abfahrt enthalten die Verspätung immer schon.")
            }

            Section {
                Picker("Hinweise", selection: $alertDisplay) {
                    ForEach(AlertDisplay.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Störungen und Bauarbeiten")
            } footer: {
                Text("„Nur für meinen Abschnitt“ zeigt einen Hinweis, wenn seine Überschrift eine Haltestelle deiner Strecke nennt. „Alle zur Linie“ zeigt jeden Hinweis, den der Verkehrsverbund der Linie zuordnet.")
            }

            Section {
                Toggle("Ausgefallene Fahrten ausblenden", isOn: $hideCancelled)
            } header: {
                Text("Ausfälle")
            } footer: {
                Text("Ausgefallene Fahrten erscheinen sonst rot und durchgestrichen – im Abfahrtsmonitor, in der Verbindungssuche und in den Widgets.")
            }

            Section {
                Picker("Zwischenhalte", selection: $stopListExpansion) {
                    ForEach(StopListExpansion.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Zwischenhalte in den Fahrtdetails")
            } footer: {
                Text("Antippen von „… Zwischenhalte“ klappt sie jederzeit auf oder zu. Im Fahrtverlauf aus dem Abfahrtsmonitor sind sie immer offen, damit deine Haltestelle zu sehen ist.")
            }
        }
        .navigationTitle("Anzeige")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

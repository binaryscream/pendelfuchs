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
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system
    @AppStorage(DataSources.useVVOKey, store: AppGroup.defaults) private var useVVO = true
    @AppStorage(DelayDisplay.storageKey, store: AppGroup.defaults) private var delayDisplay = DelayDisplay.badge
    @AppStorage(StopNameStyle.storageKey, store: AppGroup.defaults) private var stopNameStyle = StopNameStyle.withPlace
    @AppStorage(StopListExpansion.storageKey) private var stopListExpansion = StopListExpansion.collapsed

    var body: some View {
        NavigationStack {
            Form {
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
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}

private extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

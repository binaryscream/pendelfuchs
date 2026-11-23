// SPDX-License-Identifier: GPL-3.0-or-later

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
    @Environment(\.dismiss) private var dismiss

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

                Section("Über") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    LabeledContent("Daten", value: "VVO / DVB")
                    LabeledContent("Lizenz", value: "GPL-3.0")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
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

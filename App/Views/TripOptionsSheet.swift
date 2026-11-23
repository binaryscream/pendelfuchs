// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Sucheinstellungen: Deutschlandticket, Umstiege, Gehgeschwindigkeit, Verkehrsmittel.
struct TripOptionsSheet: View {
    @Binding var options: TripOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $options.deutschlandTicketOnly) {
                        Label("Nur Deutschlandticket", systemImage: "ticket")
                    }
                } footer: {
                    Text("Zeigt nur Verbindungen mit Nahverkehr – ohne ICE, IC, EC, Nachtzug und Fernbus.")
                }

                Section("Umstiege") {
                    Picker("Höchstens", selection: $options.maxTransfers) {
                        Text("Beliebig").tag(Int?.none)
                        Text("Ohne Umstieg").tag(Int?.some(0))
                        Text("1 Umstieg").tag(Int?.some(1))
                        Text("2 Umstiege").tag(Int?.some(2))
                        Text("3 Umstiege").tag(Int?.some(3))
                    }
                }

                Section {
                    Picker("Gehgeschwindigkeit", selection: $options.walkingSpeed) {
                        ForEach(WalkingSpeed.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Gehgeschwindigkeit")
                } footer: {
                    Text("Bestimmt, wie viel Zeit für Fußwege und Umstiege eingeplant wird.")
                }

                Section {
                    ForEach(ModeGroup.allCases) { group in
                        let blockedByTicket = options.deutschlandTicketOnly && !group.isDeutschlandTicketValid
                        Toggle(isOn: modeBinding(group)) {
                            Label(group.displayName, systemImage: group.symbolName)
                        }
                        .disabled(blockedByTicket)
                    }
                } header: {
                    Text("Verkehrsmittel")
                } footer: {
                    if options.allowedModes.isEmpty {
                        Text("Mindestens ein Verkehrsmittel muss ausgewählt sein.").foregroundStyle(.red)
                    } else if options.deutschlandTicketOnly {
                        Text("Fernzug und Fernbus sind beim Deutschlandticket ausgeschlossen.")
                    }
                }

                if !options.isStandard {
                    Section {
                        Button("Zurücksetzen", role: .destructive) { options = .standard }
                    }
                }
            }
            .navigationTitle("Optionen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .disabled(options.allowedModes.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func modeBinding(_ group: ModeGroup) -> Binding<Bool> {
        Binding(
            get: { !options.excludedModes.contains(group) && (!options.deutschlandTicketOnly || group.isDeutschlandTicketValid) },
            set: { isOn in
                if isOn { options.excludedModes.remove(group) } else { options.excludedModes.insert(group) }
            }
        )
    }
}

extension ModeGroup {
    var symbolName: String {
        switch self {
        case .regionalRail: "train.side.front.car"
        case .longDistance: "train.side.rear.car"
        case .subway: "tram.tunnel.fill"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .coach: "bus.doubledecker.fill"
        case .ferry: "ferry.fill"
        case .cableway: "cablecar.fill"
        case .onDemand: "car.fill"
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI
import WidgetKit

/// Einstellungen: wann regelmäßige Fahrten aussetzen – an Feiertagen und während einer Pause (Urlaub).
struct ScheduleSettingsView: View {
    @AppStorage(TripSchedule.skipHolidaysKey, store: AppGroup.defaults) private var skipHolidays = true
    /// Beginn und Ende der Pause als Zeitstempel; 0 = keine Pause.
    @AppStorage(TripSchedule.pauseFromKey, store: AppGroup.defaults) private var pauseFrom = 0.0
    @AppStorage(TripSchedule.pauseUntilKey, store: AppGroup.defaults) private var pauseUntil = 0.0
    /// Kürzel des gewählten Bundeslands; leer = automatisch nach der Starthaltestelle.
    @AppStorage(TripSchedule.stateKey, store: AppGroup.defaults) private var stateCode = ""

    @Environment(SavedTripsStore.self) private var store

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }

    /// Läuft eine Pause oder steht eine bevor? Eine abgelaufene zählt nicht mehr.
    private var hasPause: Bool {
        pauseUntil > 0 && calendar.startOfDay(for: Date(timeIntervalSince1970: pauseUntil)) >= today
    }

    var body: some View {
        Form {
            Section {
                Toggle("Pause (Urlaub)", isOn: Binding(
                    get: { hasPause },
                    set: { isOn in
                        if isOn {
                            pauseFrom = today.timeIntervalSince1970
                            pauseUntil = (calendar.date(byAdding: .day, value: 7, to: today) ?? today).timeIntervalSince1970
                        } else {
                            pauseFrom = 0
                            pauseUntil = 0
                        }
                    }))
                if hasPause {
                    DatePicker("Von", selection: Binding(
                        get: { Date(timeIntervalSince1970: pauseFrom) },
                        set: { date in
                            pauseFrom = calendar.startOfDay(for: date).timeIntervalSince1970
                            if pauseUntil < pauseFrom { pauseUntil = pauseFrom }
                        }), displayedComponents: .date)
                    DatePicker("Bis einschließlich", selection: Binding(
                        get: { Date(timeIntervalSince1970: pauseUntil) },
                        set: { pauseUntil = calendar.startOfDay(for: $0).timeIntervalSince1970 }),
                               in: Date(timeIntervalSince1970: pauseFrom)..., displayedComponents: .date)
                }
            } footer: {
                Text("In der Pause setzen alle regelmäßigen Fahrten aus: keine Erinnerungen, keine Meldungen, und „Meine nächste Fahrt“ zeigt den ersten Termin danach. Die Pause endet von selbst.")
            }

            Section {
                Toggle("An Feiertagen aussetzen", isOn: $skipHolidays)
                if skipHolidays {
                    Picker("Bundesland", selection: $stateCode) {
                        Text(automaticLabel).tag("")
                        ForEach(FederalState.allCases.sorted { $0.name < $1.name }, id: \.rawValue) {
                            Text($0.name).tag($0.rawValue)
                        }
                    }
                }
            } footer: {
                Text(holidayFooter)
            }

            if skipHolidays {
                ForEach(holidayLists, id: \.title) { list in
                    Section(list.title) {
                        ForEach(list.days, id: \.day) { holiday in
                            LabeledContent(holiday.name,
                                           value: holiday.day.formatted(.dateTime.weekday(.abbreviated).day().month().year()))
                        }
                    }
                }
            }
        }
        .navigationTitle("Feiertage & Urlaub")
        .onChange(of: stateCode) {
            WidgetCenter.shared.reloadAllTimelines()
            Task { await TripNotifier.shared.scheduleReminders() }
        }
        .onChange(of: [skipHolidays ? 1 : 0, pauseFrom, pauseUntil]) {
            WidgetCenter.shared.reloadAllTimelines()
            Task { await TripNotifier.shared.scheduleReminders() }
        }
    }

    private var chosenState: FederalState? { FederalState(rawValue: stateCode) }

    /// Bundesländer der regelmäßigen Fahrten (nach Starthaltestelle).
    private var tripStates: [FederalState] {
        var seen: [FederalState] = []
        for saved in store.trips where saved.isRegular {
            if let state = FederalState.of(saved.origin), !seen.contains(state) { seen.append(state) }
        }
        return seen
    }

    private var automaticLabel: String {
        tripStates.isEmpty ? "Automatisch" : "Automatisch (\(tripStates.map(\.name).joined(separator: ", ")))"
    }

    private var holidayFooter: String {
        guard skipHolidays else {
            return "Regelmäßige Fahrten finden auch an Feiertagen statt."
        }
        let which = chosenState == nil
            ? "„Automatisch“ nimmt für jede Fahrt das Bundesland ihrer Starthaltestelle."
            : "Für alle Fahrten gelten die Feiertage von \(chosenState!.name)."
        return which + " Feiertage, die nur in einzelnen Gemeinden gelten, sind nicht dabei."
    }

    /// Kommende Feiertage: für das gewählte Land, sonst je Land der Fahrten (ohne Fahrten: bundesweit).
    private var holidayLists: [(title: String, days: [(day: Date, name: String)])] {
        var states: [FederalState?] = [nil]
        if let chosenState { states = [chosenState] } else if !tripStates.isEmpty { states = tripStates }
        return states.map { state in
            (title: "Kommende Feiertage" + (states.count > 1 ? " · \(state?.name ?? "")" : ""),
             days: Holidays.upcoming(from: today, in: state, limit: 12, calendar: calendar))
        }
    }
}

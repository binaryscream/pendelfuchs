// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI
import UserNotifications
import WidgetKit

/// Angaben zur App, die an mehreren Stellen gebraucht werden.
enum AppInfo {
    /// Verantwortlich für die App und Ansprechpartner für Fragen zum Datenschutz.
    static let responsibleName = "Rico Kullmann"
    static let responsibleAddress = ["Lessingstraße 20", "01809 Heidenau"]

    /// E-Mail-Adresse für Fragen zur App und zum Datenschutz (Postfach bei wint.global, wie die Website).
    static let contactEmail: String? = "kontakt@pendelfuchs.de"

    /// Website mit Hilfe, Datenschutz und Impressum.
    static let websiteURL = URL(string: "https://pendelfuchs.de")!
    /// Quellcode der App (GPL-3.0; offener Code ist auch Bedingung von Transitous).
    static let sourceCodeURL = URL(string: "https://github.com/binaryscream/pendelfuchs")!

    static var contactURL: URL? {
        contactEmail.flatMap { URL(string: "mailto:\($0)?subject=Pendelfuchs") }
    }
}

/// Datenschutzhinweis in Klartext und „Daten zurücksetzen“.
struct PrivacyView: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(SavedTripsStore.self) private var savedTrips
    @Environment(RecentsStore.self) private var recents

    @State private var asking: Reset?
    @State private var done: String?

    /// Was sich zurücksetzen lässt.
    private enum Reset: String, Identifiable {
        case favorites, savedTrips, recents, everything
        var id: String { rawValue }

        var title: String {
            switch self {
            case .favorites: "Favoriten löschen?"
            case .savedTrips: "Gemerkte Fahrten löschen?"
            case .recents: "„Zuletzt verwendet“ löschen?"
            case .everything: "Alle Daten löschen?"
            }
        }

        var message: String {
            switch self {
            case .favorites: "Alle Favoriten-Haltestellen werden entfernt. Widgets ohne gewählte Haltestelle zeigen dann nichts mehr."
            case .savedTrips: "Alle gemerkten und regelmäßigen Fahrten werden entfernt – samt Erinnerungen, Benachrichtigungen und laufenden Live-Aktivitäten."
            case .recents: "Zuletzt verwendete Haltestellen, zuletzt gesuchte Strecken sowie Start und Ziel der letzten Suche werden entfernt."
            case .everything: "Favoriten, gemerkte Fahrten, „Zuletzt verwendet“ und der gemerkte Standort werden entfernt. Deine Einstellungen bleiben erhalten."
            }
        }

        var confirm: String {
            switch self {
            case .everything: "Alles löschen"
            default: "Löschen"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Label("Kein Konto, keine Werbung, kein Tracking", systemImage: "checkmark.shield")
                    .font(.body.weight(.medium))
                Text("Pendelfuchs hat keinen eigenen Server. Die App sammelt keine Daten über dich und wertet deine Nutzung nicht aus.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                item("iphone", "Auf deinem iPhone",
                     "Favoriten, gemerkte Fahrten, „Zuletzt verwendet“, deine Einstellungen und – auf etwa einen Kilometer gerundet – dein zuletzt bekannter Standort, damit Widgets in deiner Gegend suchen. Nichts davon wird an uns übertragen; es gibt niemanden, der es empfangen könnte.")
            } header: {
                Text("Was gespeichert wird")
            }

            Section {
                item("tram", "Fahrplandienste",
                     "Für Abfahrten und Verbindungen fragt die App Transitous, und – solange „Daten der Verkehrsverbünde“ eingeschaltet ist – im Gebiet des Verkehrsverbunds Oberelbe den VVO sowie in Chemnitz/Mittelsachsen, im Vogtland, in Bayern, Baden-Württemberg, Nordrhein-Westfalen und Mecklenburg-Vorpommern die Auskunft des jeweiligen Verbunds. Übertragen werden die gesuchten Haltestellen, Strecken und Zeiten.")
                item("location", "Standort",
                     "Nur wenn du ihn freigibst und nur, während du die App benutzt: Für „In der Nähe“ gehen deine Koordinaten an den Fahrplandienst, der die Haltestellen im Umkreis liefert. Eine Standortabfrage im Hintergrund gibt es nicht.")
                item("map", "Karte",
                     "Die Kartenkacheln kommen von OpenFreeMap. Der Dienst erfährt dabei, welchen Kartenausschnitt du ansiehst.")
                item("dot.radiowaves.left.and.right", "Live-Fahrzeuge in Dresden",
                     "Bei Straßenbahnen und Stadtbussen in Dresden ruft die App die Fahrzeugpositionen von TLMS ab. Die Abfrage enthält keine Angaben zu dir oder deiner Fahrt.")
                item("network", "Bei jeder Abfrage",
                     "Wie bei jedem Internetzugriff sieht der jeweilige Dienst deine IP-Adresse. Die Fahrplandienste und TLMS erhalten außerdem den Namen und die Version der App (z. B. „Pendelfuchs/1.0“) mit der Adresse pendelfuchs.de, damit sie die Anfragen der App zuordnen können – eine Kennung für dich oder dein Gerät ist das nicht. Für den Umgang damit gelten die Datenschutzhinweise der Dienste.")
            } header: {
                Text("Was dein iPhone verlässt")
            } footer: {
                Text("„Ticket bei der DB suchen“ öffnet bahn.de bzw. den DB Navigator erst, wenn du darauf tippst. Benachrichtigungen, Erinnerungen und Siri-Antworten entstehen auf dem Gerät.")
            }

            Section {
                Link("Transitous", destination: URL(string: "https://transitous.org")!)
                Link("Verkehrsverbund Oberelbe (VVO)", destination: URL(string: "https://www.vvo-online.de/de/datenschutz")!)
                Link("OpenFreeMap", destination: URL(string: "https://openfreemap.org")!)
                Link("TLMS", destination: URL(string: "https://tlm.solutions")!)
            } header: {
                Text("Die Dienste")
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppInfo.responsibleName).font(.body.weight(.medium))
                        ForEach(AppInfo.responsibleAddress, id: \.self) { Text($0).foregroundStyle(.secondary) }
                    }
                } icon: {
                    Image(systemName: "person.text.rectangle")
                }
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)
                if let mail = AppInfo.contactURL, let address = AppInfo.contactEmail {
                    Link(destination: mail) { Label(address, systemImage: "envelope") }
                }
            } header: {
                Text("Verantwortlich und Kontakt")
            } footer: {
                Text("Für Fragen zur App und zum Datenschutz.")
            }

            Section {
                resetButton("Favoriten löschen", .favorites, count: favorites.stops.count)
                resetButton("Gemerkte Fahrten löschen", .savedTrips, count: savedTrips.trips.count)
                resetButton("„Zuletzt verwendet“ löschen", .recents, count: recents.stops.count + recents.routes.count)
                Button("Alle Daten löschen", role: .destructive) { asking = .everything }
            } header: {
                Text("Daten zurücksetzen")
            } footer: {
                Text(done ?? "Löscht nur, was auf diesem iPhone liegt. Das lässt sich nicht rückgängig machen.")
            }
        }
        .navigationTitle("Datenschutz & Daten")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(asking?.title ?? "", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { choice in
            Button(choice.confirm, role: .destructive) { perform(choice) }
        } message: { choice in
            Text(choice.message)
        }
    }

    private func item(_ symbol: String, _ title: String, _ text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
        .padding(.vertical, 2)
    }

    private func resetButton(_ title: String, _ reset: Reset, count: Int) -> some View {
        Button(role: .destructive) {
            asking = reset
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .disabled(count == 0)
    }

    private func perform(_ reset: Reset) {
        switch reset {
        case .favorites:
            favorites.removeAll()
            done = "Favoriten gelöscht."
        case .savedTrips:
            clearSavedTrips()
            done = "Gemerkte Fahrten gelöscht."
        case .recents:
            clearRecents()
            done = "„Zuletzt verwendet“ gelöscht."
        case .everything:
            favorites.removeAll()
            clearSavedTrips()
            clearRecents()
            for key in ["lastLocation.v1", "memory.cancelledDepartures.v1"] { AppGroup.defaults.removeObject(forKey: key) }
            done = "Alle Daten gelöscht."
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Gemerkte Fahrten samt allem, was an ihnen hängt: Live-Aktivitäten, Erinnerungen, Meldungsgedächtnis.
    private func clearSavedTrips() {
        savedTrips.removeAll()
        TripNotifier.shared.forgetMemories()
        Task {
            await TripActivityManager.shared.endAll()
            await TripNotifier.shared.scheduleReminders()
        }
    }

    private func clearRecents() {
        recents.clear()
        // Start und Ziel der letzten Suche stehen im Formular „Verbindungen“.
        for key in ["tripSearch.origin", "tripSearch.destination"] { UserDefaults.standard.removeObject(forKey: key) }
    }
}

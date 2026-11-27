// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Häufige Fragen – erklärt vor allem, was die App ohne eigenen Server kann und was nicht.
struct FAQView: View {
    @State private var query = ""

    var body: some View {
        List {
            ForEach(visibleTopics) { topic in
                Section(topic.title) {
                    ForEach(topic.entries) { entry in
                        // Bei einer Suche gleich aufgeklappt, damit der Treffer zu sehen ist.
                        FAQRow(entry: entry, startsExpanded: !query.isEmpty)
                    }
                }
            }
            if visibleTopics.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Hilfe & Fragen")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Frage suchen")
    }

    private var visibleTopics: [FAQTopic] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return FAQTopic.all }
        return FAQTopic.all.compactMap { topic in
            let hits = topic.entries.filter {
                $0.question.localizedCaseInsensitiveContains(needle) || $0.answer.localizedCaseInsensitiveContains(needle)
            }
            return hits.isEmpty ? nil : FAQTopic(title: topic.title, entries: hits)
        }
    }
}

private struct FAQRow: View {
    let entry: FAQEntry
    let startsExpanded: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(entry.answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        } label: {
            Text(entry.question).font(.body.weight(.medium))
        }
        .onAppear { if startsExpanded { expanded = true } }
        .onChange(of: startsExpanded) { _, value in expanded = value }
    }
}

struct FAQEntry: Identifiable {
    let question: String
    let answer: String
    var id: String { question }
}

struct FAQTopic: Identifiable {
    let title: String
    let entries: [FAQEntry]
    var id: String { title }

    static let all: [FAQTopic] = [
        FAQTopic(title: "Erste Schritte", entries: [
            FAQEntry(question: "Wie lege ich einen Favoriten an?",
                     answer: "Öffne eine Haltestelle und tippe oben rechts auf den Stern. In der Suche und bei „In der Nähe“ geht es auch per Wischen nach rechts. Favoriten stehen ganz oben auf der Startseite; über „Bearbeiten“ sortierst oder löschst du sie."),
            FAQEntry(question: "Wie merke ich mir eine Fahrt?",
                     answer: "Suche unter „Verbindungen“ eine Verbindung, öffne sie und tippe auf den Stern. Danach kannst du Wochentage wählen – dann wird daraus eine regelmäßige Fahrt mit Erinnerung und Benachrichtigungen. Alle gemerkten Fahrten findest du unter „Meine Fahrten“."),
            FAQEntry(question: "Was ist der Unterschied zwischen „gemerkt“ und „regelmäßig“?",
                     answer: "Eine gemerkte Fahrt ist ein Lesezeichen. Eine regelmäßige Fahrt hat Wochentage: Die App kennt dann den nächsten Termin, erinnert dich vor der Abfahrt und meldet Ausfall, Verspätung, Gleiswechsel und Anschlussprobleme."),
            FAQEntry(question: "Warum zeigt „Aktueller Standort“ eine Haltestelle an?",
                     answer: "Die App rechnet von Haltestelle zu Haltestelle. „Aktueller Standort“ wählt deshalb die nächstgelegene Haltestelle; den Fußweg von deiner genauen Position dorthin rechnet sie nicht ein."),
        ]),
        FAQTopic(title: "Live-Aktivität", entries: [
            FAQEntry(question: "Wie starte ich die Live-Aktivität?",
                     answer: "In einer Verbindung oder gemerkten Fahrt über „Live-Aktivität starten“. Schneller geht es mit dem Knopf „Live“ im Widget „Meine nächste Fahrt“, über die Erinnerung vor der Abfahrt (Meldung gedrückt halten) oder mit Siri."),
            FAQEntry(question: "Warum bleibt die Live-Aktivität manchmal stehen?",
                     answer: "Die App hat keinen eigenen Server, der neue Daten aufs iPhone schickt. Countdown und Fortschritt laufen von selbst, neue Echtzeitdaten kommen aber nur, wenn die App offen ist oder iOS sie im Hintergrund kurz weckt – das ist nicht garantiert. Bei Fahrten mit Umstieg kann die Anzeige deshalb in einer Phase hängen bleiben. Der Knopf „Aktualisieren“ in der Aktivität holt sie wieder ein."),
            FAQEntry(question: "Was bedeutet „Stand 17:23“?",
                     answer: "Das ist die Uhrzeit der letzten erfolgreichen Abfrage. Wird die Angabe orange, sind die Daten älter als 15 Minuten – dann lohnt sich „Aktualisieren“."),
            FAQEntry(question: "Wann endet die Live-Aktivität?",
                     answer: "Von selbst etwa fünf Minuten nach der Ankunft, sobald die App das nächste Mal läuft. Sofort beendest du sie mit dem Knopf ✕ in der Aktivität, in der App oder mit Siri."),
            FAQEntry(question: "Was zeigt die Dynamic Island?",
                     answer: "Links die Linie, rechts einen Countdown bis zur Abfahrt bzw. bis zum Ausstieg. Liegt das Ziel mehr als eine Stunde entfernt, steht dort die Uhrzeit. Bei einem Ausfall erscheint ein rotes Warnzeichen."),
        ]),
        FAQTopic(title: "Benachrichtigungen", entries: [
            FAQEntry(question: "Worüber benachrichtigt die App?",
                     answer: "Bei regelmäßigen Fahrten und Fahrten mit laufender Live-Aktivität: Ausfall, Verspätung ab einer einstellbaren Schwelle, Gleis- und Steigwechsel sowie verpasste oder knappe Anschlüsse – ab einer Stunde vor der Abfahrt bis zur Ankunft. Dazu kommt die Erinnerung vor der Abfahrt."),
            FAQEntry(question: "Warum kommt eine Meldung spät oder gar nicht?",
                     answer: "Ohne eigenen Server prüft die App selbst: jede Minute, solange sie offen ist, und im Hintergrund nur, wenn iOS sie weckt. Das passiert oft nur alle 15 Minuten oder seltener. Die Erinnerung vor der Abfahrt ist davon ausgenommen – sie ist fest eingeplant und kommt pünktlich."),
            FAQEntry(question: "Warum nennt die Erinnerung keine Verspätung?",
                     answer: "Sie wird im Voraus nach dem Fahrplan eingeplant. Eine Verspätung meldet die App getrennt, sobald sie sie bemerkt."),
            FAQEntry(question: "Wo ist der Knopf „Live-Aktivität starten“ in der Erinnerung?",
                     answer: "Halte die Meldung gedrückt oder ziehe sie nach unten – dann erscheint der Knopf. Er öffnet die App und startet die Aktivität."),
            FAQEntry(question: "Wie schalte ich Meldungen für eine einzelne Fahrt aus?",
                     answer: "Öffne die Fahrt unter „Meine Fahrten“, tippe oben rechts auf die Regler und schalte „Benachrichtigungen“ aus. Alles andere stellst du unter Einstellungen → Benachrichtigungen ein."),
        ]),
        FAQTopic(title: "Widgets", entries: [
            FAQEntry(question: "Welche Widgets gibt es?",
                     answer: "„Abfahrten“ zeigt die nächsten Abfahrten einer Haltestelle. „Strecke“ zeigt die nächsten Verbindungen von A nach B und wechselt auf Wunsch ab einer Uhrzeit auf den Rückweg. „Meine nächste Fahrt“ zeigt Abfahrt, Gleis und Stand deiner nächsten gemerkten Fahrt, mit Knopf für die Live-Aktivität."),
            FAQEntry(question: "Wie füge ich ein Widget hinzu?",
                     answer: "Halte eine freie Stelle auf dem Home-Bildschirm gedrückt, tippe auf „Bearbeiten“ und „Widget hinzufügen“ und suche nach Pendelfuchs. Halte das Widget danach gedrückt und wähle „Widget bearbeiten“, um Haltestelle, Strecke oder Fahrt festzulegen."),
            FAQEntry(question: "Warum zeigt ein Widget alte Zeiten?",
                     answer: "iOS bestimmt, wie oft ein Widget neu laden darf. Die App plant deshalb etwa 45 Minuten voraus. Lädt iOS noch später, zeigt das Abfahrten-Widget Uhrzeiten statt Minuten, damit die Angabe stimmt. Antippen öffnet die App mit frischen Daten."),
            FAQEntry(question: "Wann erscheint der Knopf „Live“ im Widget?",
                     answer: "Ab drei Stunden vor der Abfahrt bis zur Ankunft – und nur, wenn die Fahrt nicht ausfällt."),
        ]),
        FAQTopic(title: "Siri und Kurzbefehle", entries: [
            FAQEntry(question: "Was kann ich Siri fragen?",
                     answer: "Zum Beispiel: „Abfahrten in Pendelfuchs“, „Wie fährt meine Fahrt in Pendelfuchs“, „Verbindung nach Pirna Bahnhof in Pendelfuchs“, „Live-Aktivität in Pendelfuchs starten“ und „Live-Aktivität in Pendelfuchs beenden“. Der App-Name muss im Satz vorkommen."),
            FAQEntry(question: "Warum fragt Siri bei einer Verbindung nach dem Start?",
                     answer: "iOS erlaubt in solchen Sätzen nur eine Haltestelle. Du nennst das Ziel, nach dem Start fragt Siri nach. Die Antwort nutzt deine Suchoptionen aus dem Tab „Verbindungen“."),
            FAQEntry(question: "Kann die Live-Aktivität von selbst starten?",
                     answer: "Ja, mit einer Automation: In der Kurzbefehle-App eine Automation „Tageszeit“ anlegen, „Sofort ausführen“ wählen und die Aktion „Live-Aktivität starten“ von Pendelfuchs hinzufügen. Einfacher ist meist der Knopf in der Erinnerung oder im Widget."),
        ]),
        FAQTopic(title: "Verbindungen und Ersatz", entries: [
            FAQEntry(question: "Was macht der Verpass-Assistent?",
                     answer: "Fällt deine gemerkte Fahrt aus oder ist ein Anschluss laut Echtzeit nicht mehr zu schaffen, zeigen Übersicht, Widget und Live-Aktivität automatisch die nächste passende Verbindung, mit einem Hinweis, warum. Du kannst ihn je Fahrt ausschalten."),
            FAQEntry(question: "Was sind die Suchoptionen einer gemerkten Fahrt?",
                     answer: "Die Einstellungen, mit denen du die Fahrt gefunden hast – etwa „Nur Deutschlandticket“, höchstens ein Umstieg oder bestimmte Verkehrsmittel. Sie gelten bei jeder neuen Suche der Fahrt, auch für den Ersatz. Ändern kannst du sie in den Einstellungen der Fahrt."),
            FAQEntry(question: "Warum heißt es „fällt aus“, obwohl die Bahn fährt?",
                     answer: "Als ausgefallen gilt eine Fahrt, wenn sie ganz entfällt oder dein Ein- oder Ausstieg nicht bedient wird. Ein übersprungener Zwischenhalt allein zählt nicht."),
            FAQEntry(question: "Kann ich in der App Tickets kaufen?",
                     answer: "Nein. „Ticket bei der DB suchen“ öffnet die Verbindungssuche von bahn.de bzw. den DB Navigator mit Start, Ziel und Uhrzeit. Fahrpreise zeigt die App nur im VVO-Gebiet an."),
        ]),
        FAQTopic(title: "Daten und Datenschutz", entries: [
            FAQEntry(question: "Woher kommen die Fahrplandaten?",
                     answer: "Für ganz Deutschland von Transitous, einem freien Gemeinschaftsprojekt. Im Gebiet des Verkehrsverbunds Oberelbe (Dresden, Meißen, Pirna, Bautzen …) nutzt die App zusätzlich die Daten des VVO, mit Fahrpreisen und Auslastung. Das lässt sich in den Einstellungen abschalten."),
            FAQEntry(question: "Was bedeutet „LIVE“ auf der Karte und in der Fahrt?",
                     answer: "Für Straßenbahnen und Stadtbusse in Dresden zeigt die App die gemeldete Position des Fahrzeugs (Quelle: TLMS). Überall sonst ist die Position aus Fahrplan und Echtzeit geschätzt."),
            FAQEntry(question: "Warum gibt es keine Wagenreihung und Zugauslastung?",
                     answer: "Diese Daten gibt die Deutsche Bahn nur an Verkehrsunternehmen mit Vertrag heraus. Auslastung zeigt die App dort, wo der VVO sie liefert."),
            FAQEntry(question: "Welche Daten verlassen mein iPhone?",
                     answer: "Es gibt kein Konto, keine Werbung und kein Tracking. Favoriten, gemerkte Fahrten und „Zuletzt verwendet“ liegen nur auf deinem Gerät. An die Fahrplandienste gehen die Anfragen selbst: gesuchte Haltestellen, Verbindungen und – für „In der Nähe“ – dein Standort."),
            FAQEntry(question: "Wie lösche ich „Zuletzt verwendet“?",
                     answer: "Wische einen Eintrag nach links und tippe auf „Entfernen“ – auf der Startseite bei den Haltestellen, im Tab „Verbindungen“ bei den zuletzt gesuchten Strecken."),
        ]),
    ]
}

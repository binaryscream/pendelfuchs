# Pendelfuchs

> Früherer Arbeitsname: „Fahrplan XL“. Projektordner und Xcode-Projekt (`FahrplanXL`) heißen deshalb noch so.
> Bundle-ID ist `de.pendelfuchs.app` (bis 27.11.2026: `de.fahrplanxl.app`).

Open-Source-Fahrplan-App für iOS 18+ (SwiftUI). Lizenz: GPL-3.0 (siehe `LICENSE`).
Website mit Hilfe, Datenschutz und Impressum: [pendelfuchs.de](https://pendelfuchs.de).

Karte: [MapLibre](https://maplibre.org) (BSD-2-Clause) mit Kacheln von [OpenFreeMap](https://openfreemap.org)
(© OpenMapTiles, Daten © OpenStreetMap-Mitwirkende).

Fahrplandaten: [Transitous](https://transitous.org/sources/) (ganz Deutschland), dazu – abschaltbar – die
VVO-WebAPI im Gebiet des Verkehrsverbunds Oberelbe und die Auskunft regionaler Verbünde (Chemnitz/Mittelsachsen,
Vogtland, Bayern, Baden-Württemberg, NRW, Mecklenburg-Vorpommern) über
[TripKit](https://github.com/binaryscream/tripkit) (Fork mit eigenem User-Agent). Live-Positionen von Straßenbahn
und Stadtbus in Dresden: [TLMS](https://tlm.solutions). Details und Nutzungsbedingungen: `docs/DATENQUELLEN.md`.

## Funktionen

- **Abfahrten** für Favoriten, zuletzt verwendete Haltestellen und Haltestellen in der Nähe; Linien- und
  Richtungsfilter, Früher/Später, Fahrtverlauf mit Zeitleiste
- **Verbindungssuche** (Von – Nach – optionaler Zwischenhalt – Zeit) mit Suchoptionen (Deutschlandticket, Umstiege,
  Gehgeschwindigkeit, Verkehrsmittel), zuletzt gesuchten Strecken und „Aktueller Standort“ als nächste Haltestelle
- **Meine Fahrten**: Verbindungen merken, als regelmäßige Fahrt an Wochentagen speichern; Verpass-Assistent
  (Ersatz bei Ausfall oder verpasstem Anschluss) mit den Suchoptionen der Fahrt
- **Live-Aktivität** (Sperrbildschirm, Dynamic Island mit Countdown) – Start per Knopf, Widget, Erinnerung,
  Siri oder Kurzbefehle-Automation
- **Benachrichtigungen** (lokal, ohne Server): Ausfall, Verspätung, Gleiswechsel, Anschlussprobleme und eine fest
  eingeplante Erinnerung vor der Abfahrt mit Knopf „Live-Aktivität starten“
- **Widgets**: „Abfahrten“, „Strecke“ (mit Rückweg und Tausch-Knopf) und „Meine nächste Fahrt“
- **Siri**: Abfahrten, Stand einer gemerkten Fahrt, Verbindung suchen, Live-Aktivität starten und beenden
- **Regionale Verbünde** (Sachsen außerhalb des VVO, Bayern, Baden-Württemberg, NRW, Mecklenburg-Vorpommern) über
  [TripKit](https://github.com/alexander-albers/tripkit) – zusätzlich zu Transitous, zusammen mit dem VVO abschaltbar
- **Karte** mit Streckenverlauf und Fahrzeugposition – in Dresden live aus [TLMS](https://tlm.solutions)
- **Extras**: Kalendereintrag, Link zur DB-Buchung, Hilfe-Seite (FAQ), Datenschutzhinweis, Daten zurücksetzen

Die App hat keinen eigenen Server, kein Konto, keine Werbung und kein Tracking. Was das für Live-Aktivität und
Benachrichtigungen bedeutet, steht unten und in der App unter Einstellungen → „Hilfe & Fragen“.

## Roadmap

1. ✅ Abfahrtsmonitor (VVO/DVB) mit Standort + Favoriten
2. ✅ Verbindungssuche (Von – Nach – optionaler Zwischenhalt – Datum – Uhrzeit, Früher/Später)
3. ✅ Fahrten merken und als regelmäßige Fahrt an gewählten Wochentagen (Mo–So) speichern, mit Live-Status
4. ✅ Dark Mode (System/Hell/Dunkel wählbar)
5. ✅ Live-Aktivität (Sperrbildschirm + Dynamic Island), Start per Knopf oder Kurzbefehle-Automation
6. ✅ Widget „Abfahrten“ (klein/mittel/groß + Sperrbildschirm), Haltestelle frei wählbar, Antippen öffnet die App
7. ✅ Ganz Deutschland über Transitous + Router für die Quellenwahl (VVO im VVO-Gebiet, sonst Transitous)
8. Weitere Regionen mit eigenen, detaillierteren Daten (wie VVO): pro Verbund offizielle Schnittstelle
   (EFA/TRIAS/HAFAS) und Erlaubnis klären, Provider ergänzen, Landkreise im Router zuordnen.
   TripKit (MIT) dient als technische Vorlage. Grundabdeckung für ganz Deutschland kommt schon von Transitous.
9. ✅ Fortschritt während der Fahrt und Karte mit Streckenverlauf und geschätzter Fahrzeugposition –
   in Dresden live aus [TLMS](https://tlm.solutions) (Straßenbahn und Stadtbus)
10. ✅ Zeitleiste mit Punkten, Fahrtverlauf aus dem Abfahrtsmonitor, Suchoptionen (Deutschlandticket, Umstiege, Gehgeschwindigkeit, Verkehrsmittel)
11. ✅ Verspätungsanzeige wählbar, Früher/Später im Abfahrtsmonitor, Strecken-Widget mit Rückweg und Tausch-Knopf, flüssigere Animationen
12. Optional: Push-Server, damit Live-Aktivitäten auch im Hintergrund minutengenau aktualisiert werden
13. ✅ Zuginfos: Auslastung (VVO) und Zugnummer; Verpass-Assistent pro Fahrt; Störungs-/Baustellenhinweise und Gleiswechsel
15. ✅ Live-Fahrzeuge (TLMS) in Karte, Zeitleiste und „Nächster Halt“; Widget-Suche auf die eigene Gegend begrenzt
16. ✅ Benachrichtigungen (Ausfall, Verspätung, Gleiswechsel, Anschluss), pro Fahrt schaltbar, Antippen öffnet die Fahrt
17. ✅ Linienfilter, Kalendereintrag, DB-Ticket-Link, Siri-Befehle
18. ✅ Durchsicht 11/2026: Live-Aktivität nach Phasenwechsel, Hintergrundprüfung, Ersatz bei Ausfall, Mitternacht,
    Standort-Zeitgrenze, live nachladende Verbindungsansicht u. a.
19. ✅ Widget „Meine nächste Fahrt“, Erinnerung vor der Abfahrt, „Zuletzt verwendet“, Countdown in der Dynamic
    Island, Suchoptionen an gemerkten Fahrten, FAQ, Kartenknöpfe, wählbarer Start-Tab
14. Offen (TODO):
    - Wagenreihung und Auslastung für Züge: offiziell derzeit nur für Eisenbahnunternehmen und Vertragspartner (DB API Marketplace geprüft 11/2026, siehe `docs/DATENQUELLEN.md`); alter Stand in der Git-Historie
    - Verpasster Anschluss, Stufe 2: Standort/Laufzeit einbeziehen (braucht Standort „Immer“, am besten mit Push-Server); Stufe 1 (Umstellung nach Echtzeitdaten) ist eingebaut
    - Antworten von VVO, TLMS und Transitous abwarten und umsetzen – Anfragen am 27.11.2026 versendet
      (VVO und TLMS per E-Mail, Transitous im Matrix-Raum; Texte und nächste Schritte: `docs/ANFRAGEN.md`)
    - Live-Aktivität endet nach der Ankunft nur, wenn iOS die App aufweckt – sonst erst nach bis zu 8 h (später ggf. kürzere Wartezeit oder Push-Server, siehe 12)
    - Dringliche Meldungen (Fokus durchbrechen): im Code vorbereitet, braucht die Berechtigung
      `com.apple.developer.usernotifications.time-sensitive` und damit ein bezahltes Entwicklerkonto (siehe `project.yml`)
    - Vor einer Veröffentlichung: Datenschutzhinweis rechtlich prüfen lassen (E-Mail-Adresse und Website
      `pendelfuchs.de` mit Hilfe- und Datenschutzseite sind seit 27.11.2026 da)
    - Regionale Verbünde über TripKit nutzen inoffizielle Schnittstellen – vor einer Veröffentlichung je Verbund
      Erlaubnis klären oder auf offizielle Angebote umsteigen (`docs/DATENQUELLEN.md`, `docs/REGIONEN.md`)
    - Offizielle VVO-Schnittstellen prüfen (TRIAS, SIRI-ET) statt der inoffiziellen WebAPI – je nach Antwort des VVO
    - Ohne Zustimmung von TLMS die Live-Positionen vor einer Veröffentlichung abschalten (siehe `docs/ANFRAGEN.md`)
    - Am Gerät prüfen: Benachrichtigungen im Hintergrund, Erinnerung, Siri per Sprache, Live-Aktivität bei
      Umstiegen, VoiceOver in den Widgets

### Hinweise zur Live-Aktivität und zu Benachrichtigungen

- Countdown und Fortschrittsbalken laufen auf dem Gerät selbst weiter (kein Server nötig).
- Die noch offenen Fahrten (höchstens zwei) stehen mit ihren Zeiten in der Aktivität; erledigte fallen heraus.
- iOS zeichnet die Aktivität ohne die App nur einmal neu, zum nächsten Phasenwechsel (Abfahrt, Umstieg, Ankunft).
  Für jeden weiteren Wechsel muss die App kurz laufen. Bei Fahrten mit Umstieg kann die Anzeige deshalb stehen
  bleiben; „Stand HH:mm“ zeigt das Alter der Daten, der Knopf „↻“ holt sie wieder ein, „✕“ beendet.
- Echtzeitdaten und Benachrichtigungen werden geprüft, solange die App offen ist (jede Minute) und im
  Hintergrund, wenn iOS die App kurz weckt (`BGAppRefreshTask`, oft nur alle 15 min oder seltener, nicht garantiert).
- Die Erinnerung vor der Abfahrt ist davon ausgenommen: Sie wird als lokale Benachrichtigung fest eingeplant
  (nächste fünf Termine je Fahrt) und richtet sich nach dem Fahrplan.
- Start ohne App: Knopf „Live“ im Widget „Meine nächste Fahrt“, Knopf in der Erinnerung, Siri oder
  Kurzbefehle → Automation → Tageszeit → Aktion „Live-Aktivität starten“.

Technische Notizen zu den Datenquellen: [`docs/DATENQUELLEN.md`](docs/DATENQUELLEN.md)

## Bauen

Voraussetzungen: Xcode 16 oder neuer, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig   # eigene Team-ID eintragen (nur für Geräte-Builds)
xcodegen generate          # erzeugt FahrplanXL.xcodeproj aus project.yml
open FahrplanXL.xcodeproj
```

Die Apple-Team-ID steht nur in `Config/Local.xcconfig`; die Datei ist nicht im Repo. Für den Simulator ist sie nicht nötig.

Tests der Kernlogik (ohne Simulator):

```bash
cd Packages/FahrplanKit
swift test                          # offline, mit gespeicherten API-Antworten
FAHRPLAN_LIVE_TESTS=1 swift test    # zusätzlich gegen die echte VVO-API
```

## Aufbau

- `App/` – die iOS-App (SwiftUI): `Views/` (Ansichten), `LiveActivity/` (Live-Aktivität, Siri-Befehle),
  `Notifications/` (Benachrichtigungen und Erinnerung)
- `Shared/` – Code, den App und Widget-Erweiterung gemeinsam nutzen (Linienfarben, Live-Aktivitäts-Attribute,
  Knöpfe der Aktivität, Auswahl von Haltestellen und Fahrten, Deep Links)
- `Widgets/` – Widget-Erweiterung (Abfahrten, Strecke, Meine nächste Fahrt, Live-Aktivität); Daten teilt sie mit
  der App über die App Group `group.de.pendelfuchs.app`
- `Packages/FahrplanKit/` – gemeinsame Logik mit Tests: Datenmodelle, Datenquellen und Router, gemerkte Fahrten,
  Favoriten, zuletzt verwendet, Erkennung von Meldungen (`TripWatch`), Live-Fahrzeuge
- `docs/` – Datenquellen, Regionen, fertige Anfragen an VVO, TLMS und Transitous (`ANFRAGEN.md`), Texte und
  Antworten für App Store Connect samt Checkliste vor dem ersten Hochladen (`APP-STORE.md`)
- `App/PrivacyInfo.xcprivacy`, `Widgets/PrivacyInfo.xcprivacy` – Datenschutz-Manifeste für den App Store
- `design/pendelfuchs/` – die endgültigen App-Icons in sechs Varianten (Standard, Dunkel, Klar hell/dunkel, Getönt
  hell/dunkel). Im Asset-Katalog liegen Standard, Dunkel und eine Graustufenfassung für „Getönt“; die klaren und
  farbig getönten Varianten ließen sich nur über eine `.icon`-Datei aus Icon Composer einbinden.
  `design/app-icon-source.png` und `tools/make-app-icon.swift` gehören zum früheren Icon.
- `project.yml` – Projektbeschreibung für XcodeGen (das `.xcodeproj` wird daraus erzeugt)
- `Config/` – Signier-Einstellungen; die eigene Team-ID gehört in `Config/Local.xcconfig` (nicht im Repo)

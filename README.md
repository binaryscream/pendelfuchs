# Fahrplan XL

Open-Source-Fahrplan-App für iOS 18+ (SwiftUI). Lizenz: GPL-3.0 (siehe `LICENSE`).

Karte: [MapLibre](https://maplibre.org) (BSD-2-Clause) mit Kacheln von [OpenFreeMap](https://openfreemap.org)
(© OpenMapTiles, Daten © OpenStreetMap-Mitwirkende).

Fahrplandaten: [Transitous](https://transitous.org/sources/) (ganz Deutschland) und im Gebiet des
Verkehrsverbunds Oberelbe optional die VVO-WebAPI. Details und Nutzungsbedingungen: `docs/DATENQUELLEN.md`.

## Ziele

- **Abfahrtsmonitor** für den aktuellen Standort oder Favoriten-Haltestellen
- **Widgets** für Favoriten-Haltestellen
- **Regelmäßige Fahrten** (z. B. Mo–Fr 6:30 Zug von X nach Y)
- **Live-Aktivität** für regelmäßige Fahrten (Sperrbildschirm / Dynamic Island)
- **Intelligente Quellenwahl**: pro Verkehrsmittel/Region die beste Datenquelle
  (Zug → DB, Bus/Tram im VVO-Gebiet → VVO/DVB, …)

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
9. ✅ Fortschritt während der Fahrt und Karte mit Streckenverlauf und geschätzter Fahrzeugposition
10. ✅ Zeitleiste mit Punkten, Fahrtverlauf aus dem Abfahrtsmonitor, Suchoptionen (Deutschlandticket, Umstiege, Gehgeschwindigkeit, Verkehrsmittel)
11. ✅ Verspätungsanzeige wählbar, Früher/Später im Abfahrtsmonitor, Strecken-Widget mit Rückweg und Tausch-Knopf, flüssigere Animationen
12. Optional: Push-Server, damit Live-Aktivitäten auch im Hintergrund minutengenau aktualisiert werden
13. ✅ Zuginfos: Auslastung (VVO) und Zugnummer; Verpass-Assistent pro Fahrt; Störungs-/Baustellenhinweise und Gleiswechsel
14. Offen (TODO):
    - Wagenreihung und Auslastung für Züge, sobald es eine offizielle DB-Anbindung gibt (DB API Marketplace prüfen; alter Stand in der Git-Historie)
    - Verpasster Anschluss, Stufe 2: Standort/Laufzeit einbeziehen (braucht Standort „Immer“, am besten mit Push-Server); Stufe 1 (Umstellung nach Echtzeitdaten) ist eingebaut
    - Anfrage an den VVO versenden (Entwurf: `docs/VVO-ANFRAGE.md`)
    - Live-Aktivität endet nach der Ankunft nur, wenn iOS die App aufweckt – sonst erst nach bis zu 8 h (später ggf. kürzere Wartezeit oder Push-Server, siehe 12)
    - Offizielle VVO-Schnittstellen prüfen (TRIAS, SIRI-ET) statt der inoffiziellen WebAPI; Erlaubnis bei opendata@vvo-online.de klären
    - Fahrzeugpositionen in Dresden (TLMS) für die Karte; Quellen: <https://oepnv.dresden.lol>, <https://github.com/kiliankoe/vvo>
    - Widget-Haltestellensuche auf die Region begrenzen; Kurzbefehle-Automation testen

### Hinweise zur Live-Aktivität

- Countdown und Fortschrittsbalken laufen auf dem Gerät selbst weiter (kein Server nötig).
- Echtzeitdaten (Verspätungen) werden aktualisiert, solange die App offen ist (jede Minute) und im
  Hintergrund, wenn iOS die App kurz weckt (`BGAppRefreshTask`, ca. alle 15 min, nicht garantiert).
- Automatischer Start: Kurzbefehle → Automation → Tageszeit → Aktion „Live-Aktivität starten“.

Technische Notizen zu den Datenquellen: [`docs/DATENQUELLEN.md`](docs/DATENQUELLEN.md)

## Bauen

Voraussetzungen: Xcode 16 oder neuer, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate          # erzeugt FahrplanXL.xcodeproj aus project.yml
open FahrplanXL.xcodeproj
```

Tests der Kernlogik (ohne Simulator):

```bash
cd Packages/FahrplanKit
swift test                          # offline, mit gespeicherten API-Antworten
FAHRPLAN_LIVE_TESTS=1 swift test    # zusätzlich gegen die echte VVO-API
```

## Aufbau

- `App/` – die iOS-App (SwiftUI)
- `Shared/` – Code, den App und Widget-Erweiterung gemeinsam nutzen (Linienfarben, Live-Aktivitäts-Attribute)
- `Widgets/` – Widget-Erweiterung (Abfahrten-Widget, Live-Aktivität); Daten teilt sie mit der App über die App Group `group.de.fahrplanxl.app`
- `Packages/FahrplanKit/` – gemeinsame Logik: Datenmodelle, Datenquellen, Favoriten (später auch von Widgets genutzt)
- `design/` – Vorlage des App-Icons; `tools/make-app-icon.swift` erzeugt daraus die Icon-Varianten (`swift tools/make-app-icon.swift design/app-icon-source.png App/Assets.xcassets/AppIcon.appiconset`)
- `project.yml` – Projektbeschreibung für XcodeGen (das `.xcodeproj` wird daraus erzeugt)

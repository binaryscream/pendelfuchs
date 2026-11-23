# Fahrplan XL

Open-Source-Fahrplan-App für iOS 18+ (SwiftUI). Lizenz: GPL-3.0 (siehe `LICENSE`).

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
8. Optional: Push-Server, damit Live-Aktivitäten auch im Hintergrund minutengenau aktualisiert werden

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
- `project.yml` – Projektbeschreibung für XcodeGen (das `.xcodeproj` wird daraus erzeugt)

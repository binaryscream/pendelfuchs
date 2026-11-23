# Datenquellen – Stand 23.11.2026

## VVO / DVB – `https://webapi.vvo-online.de` ✅ getestet

Inoffizielle, aber offene JSON-API (kein API-Key), auch von `dvbjs`/`dvbpy` genutzt.
**DVB und VVO laufen über dieselbe API** – sie deckt das ganze VVO-Gebiet ab
(Dresden, Pirna, …) inkl. S-Bahn/Regionalzügen im Verbund.

Alle Aufrufe: `POST`, `Content-Type: application/json`.

| Endpunkt | Zweck | Beispiel-Body |
|---|---|---|
| `/tr/pointfinder` | Haltestellensuche | `{"query":"Pirna Bahnhof","limit":3,"stopsOnly":true}` |
| `/dm` | Abfahrten | `{"stopid":"33000028","limit":10}` |
| `/tr/trips` | Verbindungssuche | `{"origin":"33003370","destination":"33000028","isarrivaltime":false,"shorttermchanges":true}` |

Beobachtungen:
- Pointfinder liefert Strings: `"ID|Typ|Ort|Name|Hochwert|Rechtswert|Entfernung|…"` (Koordinaten in Gauß-Krüger Zone 4,
  Umrechnung in `GaussKrueger.swift`). Leerer Ort = Dresden.
- Umkreissuche: `{"query":"coord:<Rechtswert>:<Hochwert>","assignedStops":true,"stopsOnly":false}` – liefert
  zuerst die Adresse, dann Haltestellen mit Entfernung in Metern.
- Zeiten im .NET-Format: `"\/Date(1795453020000-0000)\/"` (Millisekunden seit 1970).
- Abfahrten enthalten `ScheduledTime`, `RealTime`, `State` (InTime/Delayed/…), `Platform`, `Mot` (Tram/CityBus/…), `Occupancy`.
- Verbindungen enthalten sogar Preisstufe und Preis.

Verbindungssuche (`/tr/trips`):
- Zeit als `"2026-11-24T06:30:00+01:00"` (Ortszeit mit Offset), `isarrivaltime` für Ankunftssuche.
- **Zwischenhalt heißt `Via` (groß geschrieben!)** – `via`, `vias`, `viaStop` usw. werden kommentarlos ignoriert.
- Die API liefert ein Zeitfenster um die Wunschzeit (auch etwas frühere bzw. spätere Verbindungen).
- `PartialRoutes` enthalten Fahrten (`RegularStops` mit Plan-/Echtzeit, Gleis/Steig), Fußwege (`Footpath`)
  und Barrierefreiheits-Hinweise (`MobilityStairsUp/Down` …), die die App zu einem Fußweg zusammenfasst.
- Pro Verbindung gibt es Preis (`Price`), Preisstufe und Tarifzonen (`FareZoneNames`).
- Pointfinder mit `limit: 1` liefert teils `NotIdentified` – lieber größeres Limit verwenden.

Bekannte IDs: Dresden Hbf `33000028`, Pirna Bahnhof `33003370`.

## DB ⚠️ offen

- `v6.db.transport.rest` (Community-Projekt `db-rest`): **Domain löst am 23.11.2026 nicht auf** – vermutlich eingestellt.
- Zu prüfen:
  - `db-vendo-client` (spricht direkt die bahn.de-Schnittstelle an; inoffiziell, müsste in Swift nachgebaut werden)
  - DB API Marketplace „Timetables“ (offiziell, kostenloser Key, aber nur Abfahrtstafeln, keine Verbindungssuche)
- Für Züge im VVO-Gebiet liefert die VVO-API bereits Echtzeit – DB wird v. a. für Fern- und Regionalverkehr außerhalb gebraucht.

## Architektur-Idee

Gemeinsames Protokoll `TransitProvider` (Haltestellensuche, Abfahrten, Verbindungen).
Ein `ProviderRouter` wählt je nach Verkehrsmittel und Region die Quelle und kann
Teilstrecken einer Verbindung mit Echtzeit aus der jeweils besten Quelle anreichern.

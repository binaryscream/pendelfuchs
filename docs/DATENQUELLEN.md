# Datenquellen – Stand 23.11.2026

> **Ziel: Veröffentlichung im App Store.** Apple verlangt (Richtlinie 5.2.2), dass fremde Dienste nur mit
> Erlaubnis genutzt werden. Deshalb ist bei jeder Quelle unten vermerkt, ob die Nutzung erlaubt ist.

## Übersicht und Empfehlung

| Quelle | Kann | Erlaubt für veröffentlichte App? | Rolle |
|---|---|---|---|
| **Transitous** (MOTIS 2) | Ganz Deutschland/Europa: Suche, Abfahrten, Verbindungen, Echtzeit | ✅ für kostenlose Open-Source-Apps, mit Auflagen | **Hauptquelle** |
| VVO-WebAPI | VVO-Gebiet, sehr detailliert (Preise, Auslastung) | ❓ inoffiziell, keine Bedingungen – **beim VVO anfragen** | Ergänzung, falls erlaubt |
| VVO TRIAS | VVO-Gebiet, offizielle Schnittstelle | ✅ laut Community-Doku nach Absprache | Alternative zur WebAPI |
| DB OpenBoards | Abfahrtstafeln an Bahnhöfen mit Echtzeit/Gleis | ❓ kostenlos, Lizenz unklar | Optional für Gleisinfos |
| DB RIS::Boards u. a. | Abfahrtstafeln, Fahrtverläufe | ❌ kostenpflichtig / nur DB-Vertriebspartner | – |
| db-vendo-client | DB-Navigator-Schnittstelle | ❌ inoffiziell, laut eigener Doku Erlaubnis nötig | Nicht für Veröffentlichung |

**Empfehlung:** Transitous als Hauptquelle für ganz Deutschland. Die VVO-WebAPI bleibt in der Entwicklung
aktiv; vor der Veröffentlichung schriftliche Erlaubnis bei `opendata@vvo-online.de` einholen (oder auf TRIAS wechseln).
Ohne Erlaubnis läuft die App rein über Transitous.

## Transitous – `https://api.transitous.org/api/` ✅ getestet

Gemeinschaftlich betriebener Routing-Dienst (MOTIS 2) auf Basis offener Fahrplandaten (für Deutschland:
DELFI / opendata-oepnv.de, CC BY 4.0, plus Echtzeit). OpenAPI-Spezifikation:
`https://raw.githubusercontent.com/motis-project/motis/refs/tags/v2.11.4/openapi.yaml`.

**Nutzungsbedingungen** (transitous.org/api, sinngemäß):
- Nur für **kostenlose Open-Source-Projekte**, nicht kommerziell (wegen der Datenlizenzen). Quellcode muss
  unter einer Open-Source-Lizenz veröffentlicht sein (Prototypen vorher sind ok). → Passt zu GPL-3.0, App muss gratis bleiben.
- **User-Agent** mit App-Name, Version und Kontakt (E-Mail oder URL) bei jeder Anfrage.
  → umgesetzt: `FahrplanXL/<Version> (+https://github.com/binaryscream/fahrplan-xl)`.
- **Quellenangabe:** sichtbarer Link auf `https://transitous.org/sources/` plus OpenStreetMap-Nennung.
- Viele Verbindungssuchen (> 720 `/plan`-Anfragen pro 24 h) und viele Nutzer gelten als hohe Last →
  vor einer Veröffentlichung mit vielen Nutzern im Matrix-Kanal von Transitous absprechen.
- Kein Scraping, keine Staging-/internen Hosts. Betrieb „best effort“, ohne Garantie, Zugang kann entzogen werden.
- Optional: Link zur Spendenseite.

**Getestete Endpunkte** (23.11.2026):

| Endpunkt | Zweck | Ergebnis |
|---|---|---|
| `GET /v1/geocode?text=Pirna%20Bahnhof&type=STOP` | Haltestellensuche | ✅ `de-DELFI_de:14628:3370`, mit Koordinaten (WGS84) |
| `GET /v5/stoptimes?stopId=…&n=8` | Abfahrten | ✅ Dresden Hbf: Straßenbahn, Bus, RE, Fernzug, FlixBus – mit Echtzeit (z. B. Linie 10 +7 min) und Gleis/Steig |
| `GET /v5/plan?fromPlace=…&toPlace=…` | Verbindungssuche | ✅ Pirna → Postplatz: S1 → Straßenbahn 3/7/11, Echtzeit und Gleis je Teilstrecke, Blättern per `nextPageCursor` |

Beobachtungen:
- Haltestellen-IDs sind die bundesweiten **DHIDs** mit Präfix (`de-DELFI_de:14628:3370`). Die VVO-WebAPI
  liefert dieselbe DHID im Feld `DhId` → beide Quellen lassen sich sauber zuordnen.
- Zeiten als ISO-8601 in **UTC**.
- Fernverkehr und Fernbusse sind enthalten – damit deckt Transitous auch den Teil ab, für den wir die DB brauchten.

## VVO / DVB – `https://webapi.vvo-online.de` ✅ getestet, ❓ Erlaubnis offen

**Status:** Inoffiziell. Keine veröffentlichten Nutzungsbedingungen; die Community-Doku
(github.com/kiliankoe/vvo) schreibt „No official terms, use respectfully“. Eine Open-Data-Seite des VVO
gibt es nicht (mehr) (404). Kontakt für Open-Data-/API-Fragen laut Community-Doku: `opendata@vvo-online.de`.
Dort gibt es auch eine offizielle **TRIAS**-Schnittstelle (`https://efa.vvo-online.de/std3/trias`),
„kommerzielle Nutzung nach Absprache“ (Angabe der Community-Doku, nicht vom VVO selbst bestätigt).

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

## Deutsche Bahn

- **Keine offizielle, frei nutzbare Verbindungssuche** im DB API Marketplace.
- **OpenBoards** (kostenlos, 10 Anfragen/s): Abfahrts-/Ankunftstafeln mit Echtzeit, Gleisen, Ausfällen,
  Störungen. Nutzungsrechte ergeben sich aus separaten Lizenzen (Verweis auf bahnhof.de-Bedingungen) – vor
  Einsatz in einer veröffentlichten App klären.
- **RIS::Boards / RIS::Journeys / RIS::Connections:** kostenpflichtig bzw. nur für DB-Vertriebspartner.
- Allgemeine Nutzungsbedingungen (Stand 05/2022): Inhalte nur gemäß jeweiliger Lizenz und unverändert nutzen.
- **db-vendo-client** (inoffizielle DB-Navigator-/bahn.de-Schnittstellen, ISC-Lizenz): laut eigener Doku
  „streng genommen Erlaubnis nötig“, häufige Sperren → **nicht für die veröffentlichte App**.
- `v6.db.transport.rest`: Domain löst nicht auf, eingestellt.

## Vergleich: ÖPNV Navigator (iOS) / TripKit

Die iOS-App „ÖPNV Navigator“ (Alexander Albers) ist **nicht** quelloffen; offen ist nur ihre Datenbibliothek
**TripKit** (github.com/alexander-albers/tripkit, **MIT-Lizenz**, aktiv gepflegt, Swift-Port von
`public-transport-enabler` aus Öffi). Geprüft am 23.11.2026:

- **Ansatz:** dieselben Schnittstellen, die die offiziellen Apps der Verkehrsunternehmen nutzen –
  rund 50 Anbieter (EFA, HAFAS, OJP, TRIAS …), überwiegend inoffiziell.
- **DB:** DB-Navigator-Schnittstelle `https://app.services-bahn.de/mob/` (Vendo/Movas), also derselbe Weg
  wie db-vendo-client.
- **VVO:** EFA-Schnittstelle `https://efa.vvo-online.de/std3/` (nicht unsere WebAPI).
- **Schlüssel:** Für viele Anbieter nötig (HAFAS-„aid“, Prüfsummen-Salt, Zertifikate). Im Repo nur leere
  Vorlage; laut README soll man sie beim Anbieter anfragen „oder dieselben wie die offiziellen Apps verwenden“.
- **Erlaubnis:** Keine Aussage im README zu Nutzungsbedingungen oder Vereinbarungen mit den Verbünden.

**Bewertung für Fahrplan XL:** Technisch ein gutes Nachschlagewerk (MIT, Swift, mit GPL-3.0 vereinbar),
rechtlich aber dasselbe Risiko wie db-vendo-client – inoffizielle Schnittstellen, teils mit Schlüsseln aus
fremden Apps. Für eine veröffentlichte App nicht als Grundlage geeignet; Transitous bleibt die Hauptquelle.
Sinnvoll als Vorlage, falls ein Verbund uns ausdrücklich erlaubt, seine EFA-/TRIAS-Schnittstelle zu nutzen.

## Architektur-Idee

Gemeinsames Protokoll `TransitProvider` (Haltestellensuche, Abfahrten, Verbindungen).
Ein `ProviderRouter` wählt je nach Region und Verfügbarkeit die Quelle:
- Standard überall: **Transitous**.
- Im VVO-Gebiet zusätzlich VVO (Preise, Auslastung, sehr aktuelle Echtzeit) – nur wenn die Nutzung erlaubt ist,
  per Schalter abschaltbar.
- Zuordnung zwischen Quellen über die DHID (`de:14628:3370`).
- Gemerkte Fahrten/Favoriten sollten die DHID speichern, damit ein Quellenwechsel sie nicht ungültig macht.

## Eigenheiten der VVO-WebAPI (Stand 24.11.2026, selbst geprüft)

- **`/dm/trip` kann eine andere Fahrt liefern als die angetippte Abfahrt.** Die API wählt die Fahrt über die
  *Echtzeit* aus (die `tripid` gilt für alle Fahrten einer Linie). Beispiel: eine S1 mit +8 min zeigte im Verlauf
  die 11 Minuten frühere Fahrt mit +12 min. Abhilfe in der App: zuerst mit der erwarteten Zeit fragen, die
  Plan-Abfahrt am eigenen Halt prüfen und sonst mit der Planzeit wiederholen; ist die Fahrt nicht eindeutig, gibt
  es eine Fehlermeldung statt falscher Daten. Ausgefallene Fahrten haben keinen Verlauf.
- **`/dm` kennt keine Abfahrten in der Vergangenheit** (ältere `time` springt auf „jetzt“). „Früher“ im
  Abfahrtsmonitor nutzt deshalb Transitous.
- **`standardSettings.mot` filtert den Schienenersatzverkehr (SEV) weg** – er gehört zu keinem Wert. Mit
  `mot = [CityBus]` o. Ä. fehlen SEV-Fahrten komplett. Deshalb filtert die App Fernverkehr lokal und sendet bei
  Deutschlandticket **kein** `mot`; nur bei abgewählten Nahverkehrsmitteln wird zusätzlich ohne Filter gefragt.
- `maxChanges` kennt nur `None`, `One`, `Two`, `Unlimited` (drei Umstiege nicht).
- `/tr/trips`: die API liefert auch Fahrten mit „gesichertem Anschluss“ (`StayForConnection`) und
  Schienenersatzverkehr als `Bus` mit `ProductName: "Ersatzverkehr"`.

## Weitere Quellen (Tipps)

- **oepnv.dresden.lol** (Community-Doku von kiliankoe, Quellcode: github.com/kiliankoe/vvo, Lizenz nicht angegeben):
  beschreibt WebAPI, TRIAS (`efa.vvo-online.de/std3/trias`), OJP, EFA-JSON, GTFS/GTFS-RT und SIRI. Kein eigener
  Server, nur Dokumentation.
- **TLMS** (`wss://socket.tlm.solutions`): ehrenamtlicher Live-Feed mit Fahrzeugpositionen und Verspätungen aus
  R09-Funktelegrammen (Dresden). Kandidat für echte Fahrzeugpositionen statt der geschätzten – Abdeckung hängt von
  Empfängern ab, Nutzungsbedingungen noch nicht geprüft.
- **VVO-Störungsmeldungen** (`POST /rc`): Baustellen und Störungen je Linie (Antwort > 200 kB).

## Wagenreihung (Deutsche Bahn, inoffiziell)

- `https://www.bahn.de/web/api/reisebegleitung/wagenreihung/vehicle-sequence` mit `administrationId=80`,
  `category` (S/RB/RE/IC/ICE – die Schnittstelle ist tolerant), `date` (Tag in Europe/Berlin), `evaNumber`,
  `number` (Zugnummer) und `time` (Plan-Abfahrt, ISO 8601 UTC). 404 = keine Wagenreihung.
- Die EVA-Nummer des Einstiegs holt `reiseloesung/orte/nearby?lat=&long=&radius=1000` (erste 7-stellige
  Nummer mit „80“ und Zug-Produkten).
- Die Zugnummer kommt von VVO (`Mot.TrainNumber`) bzw. Transitous (`tripShortName`).
- curl wird von bahn.de geblockt (`OPS_BLOCKED`), URLSession (iOS/macOS) funktioniert.
- **Rechtlich:** keine Erlaubnis der DB, Nutzung wie bei db-vendo auf eigenes Risiko; vor einer Veröffentlichung
  klären oder durch einen Link nach außen ersetzen. In der App als „inoffiziell, ohne Gewähr“ gekennzeichnet.
- Auslastung kommt nur vom VVO (`Occupancy` je Halt in `/tr/trips`, `/dm`, `/dm/trip`).

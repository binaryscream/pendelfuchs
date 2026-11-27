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
  → umgesetzt: `Pendelfuchs/<Version> (+https://pendelfuchs.de)` (vorher die GitHub-Adresse, seit 27.11.2026 die Website).
- **Quellenangabe:** sichtbarer Link auf `https://transitous.org/sources/` plus OpenStreetMap-Nennung.
- Viele Verbindungssuchen (> 720 `/plan`-Anfragen pro 24 h) und viele Nutzer gelten als hohe Last →
  vor einer Veröffentlichung mit vielen Nutzern im Matrix-Kanal von Transitous absprechen.
  **Abgesprochen 27.11.2026:** Transitous empfahl für wiederkehrende Abfragen `refresh-itinerary` statt `/plan` und
  „everything v6“. Umgesetzt: Gemerkte Fahrten werden einmal am Tag gesucht, danach nur noch über die
  Kennung der Verbindung abgeholt (`SavedTripLookup`, Kennungen in der App Group); neu gesucht wird nur ohne
  Kennung, bei Fehlern oder bei Ausfall/verpasstem Anschluss (für den Ersatz). Die geöffnete Verbindung lädt
  ebenfalls per Kennung nach. Alle Endpunkte laufen über v6, nur `geocode`/`reverse-geocode` gibt es nur als v1.
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

## Regionale Verbünde über TripKit ✅ eingebaut (27.11.2026)

Auf Wunsch eingebaut, **mit Vorbehalt**: Die Schnittstellen sind die Auskunftssysteme der Verbünde für ihre eigenen
Apps und Websites, für Drittanbieter nicht offiziell freigegeben (Apple-Richtlinie 5.2.2, siehe oben). Vor einer
Veröffentlichung je Verbund die Erlaubnis klären – oder auf deren offizielle Angebote (TRIAS, GTFS-RT, siehe
`docs/REGIONEN.md`) umsteigen.

- **Bibliothek:** TripKit (github.com/alexander-albers/tripkit, MIT), fest auf einen Stand gesetzt
  (`Packages/FahrplanKit/Package.swift`). Bringt GzipSwift, SwiftyJSON und SWXMLHash mit (alle MIT).
- **Nur EFA-Verbünde ohne Schlüssel:** VMS (Chemnitz, Erzgebirge, Mittelsachsen, Zwickau), VVV (Vogtland),
  Bayern-Fahrplan (ganz Bayern), NVBW (Baden-Württemberg), mobil.nrw (NRW), MV-Fahrplan (Mecklenburg-Vorpommern).
  HAFAS-Verbünde (Berlin, Köln-KVB, RMV, Österreich …) brauchen eine Kennung; Kennungen fremder Apps werden
  bewusst nicht verwendet. Das VVO-Gebiet behält die eigene WebAPI-Anbindung.
- **Zuordnung** (`RegionalNetwork.forDistrict`): über den Kreis in der bundesweiten Haltestellen-ID, unabhängig
  vom Datensatz-Präfix bei Transitous (`de-DELFI_`, `at-Railway-…_`). Die Verbund-Haltestelle wird über die Lage
  gesucht (nächste mit passendem Namen, höchstens 400 m) und für die Laufzeit der App gemerkt.
- **Router:** Abfahrten an Haltestellen im Verbundgebiet und Verbindungen, deren Start und Ziel im selben Verbund
  liegen, kommen vom Verbund; Fehler oder leeres Ergebnis → Transitous. Gemerkte Fahrten aus Verbunddaten haben
  keine `refresh-itinerary`-Kennung und werden wie VVO-Fahrten neu gesucht.
- **Fahrpreise:** Einzelfahrt Erwachsene mit Preisstufe, wo der Verbund sie liefert – VMS, VVV und mobil.nrw
  (Probe 27.11.2026: Chemnitz → Zwickau 11,50 €, Preisstufe VR); Bayern-Fahrplan, NVBW und MV-Fahrplan liefern keine.
- **Haltestellen ohne bundesweite ID** (z. B. Fernbus-Halte, die Transitous bei der Suche mit anbietet) gelten bei
  Verbindungen nicht als „außerhalb“: Liegen die übrigen Halte in einem Verbund, sucht dieser sie über die Lage.
- **Schalter:** Einstellungen → „Daten der Verkehrsverbünde“ (Standard an) gilt für VVO und TripKit-Verbünde
  gemeinsam; der frühere Schalter „VVO-Daten“ wird beim Start übernommen. Quellenangabe in den Einstellungen.
- **Live-Probe** (27.11.2026, `RegionalProviderLiveTests`, mit `FAHRPLAN_LIVE_TESTS=1` über `xcodebuild test`
  laufen lassen – `swift test` stürzt in TripKits Logging ab, weil dort keine App-Kennung existiert): alle sechs
  Verbünde liefern Abfahrten, Fahrtverläufe und Verbindungen, alle außer VVV mit Echtzeit.

## DELFI-Echtzeit und andere Apps (geprüft 27.11.2026)

**Ergebnis: kein eigener DELFI-Zugang nötig – die DELFI-Echtzeit kommt schon über Transitous.**

- **DELFI offiziell:** Seit 08/2024 bundesweite Prognosedaten (GTFS-RT Trip Updates und SIRI-ET) auf der Mobilithek
  (mobilithek.info), Bezug über „Abonnieren“ und Freischaltung durch DELFI e.V. Gedacht für Betreiber mit eigenem
  Server – ein bundesweiter Strom ist auf dem iPhone nicht sinnvoll zu verarbeiten.
- **gtfs.de:** kostenloser gebündelter GTFS-RT-Strom (`realtime.gtfs.de/realtime-free.pb`, CC BY-SA 4.0, Beta), u. a. VVO,
  VRS, VRR, NVBW, DEFAS Bayern, VBB, Bahn-Regionalverkehr, SIRI Oberelbe/Bayern/BW/MV/Hessen. VMS und Vogtland fehlen.
- **Transitous** (`feeds/de.json`) liest bereits DELFI-Fahrplan, einen DELFI-GTFS-RT-Strom, DELFI-SIRI sowie VBB, VBN, KVV
  u. a. ein und fragt jede Minute ab. Was dort ankommt, zeigt Pendelfuchs schon.
- **Wozu dann die Verbünde (VVO, TripKit)?** Preise und Auslastung gibt es nur dort, und in Regionen mit lückenhafter
  DELFI-Echtzeit (z. B. VMS, Vogtland) ist die Auskunft des Verbunds genauer.

**Wie es andere machen:**
- Große Apps (Google Maps, Apple Karten, Moovit) nutzen DELFI-Daten und eigene Verträge; Google seit 2026 mit einer
  DELFI-Kooperation für Echtzeit.
- Indie-Apps (Öffi, Transportr, ÖPNV Navigator) fragen die Auskünfte der Verbünde direkt ab (public-transport-enabler bzw.
  TripKit), meist ohne veröffentlichte Erlaubnis. F-Droid kennzeichnet Öffi deshalb mit „NonFreeNet“. Risiko:
  Schnittstellen können wegfallen (DB-HAFAS Anfang 2025 abgeschaltet).
- Pendelfuchs geht einen Schritt weiter und fragt die Verbünde vorher (`docs/ANFRAGEN.md`).

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

**Bewertung für Pendelfuchs:** Technisch ein gutes Nachschlagewerk (MIT, Swift, mit GPL-3.0 vereinbar),
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
- **TLMS** (tlm.solutions): ehrenamtlicher Live-Feed mit Fahrzeugpositionen und Verspätungen aus
  R09-Funktelegrammen (Dresden). **Wird für die Karte genutzt**, siehe unten. Nutzungsbedingungen sind nirgends
  veröffentlicht – vor einer Veröffentlichung der App beim Projekt nachfragen (hello@tlm.solutions oder Matrix
  `#dump-dvb:matrix.org`, so auf tlm.solutions verlinkt; fertiger Text: `docs/ANFRAGEN.md`).

## TLMS-Fahrzeugpositionen (Karte)

- **Erlaubnis (27.11.2026):** TLMS erlaubt die Nutzung bei maßvollem Traffic, mit Nennung in der App und einem
  eindeutigen User-Agent (`Pendelfuchs/<Version> (+<Kontakt-URL>)`, gesetzt in `TLMSClient`).
- **Abfrage:** `GET https://lizard.tlm.solutions/v1/vehicles/0` (Region 0 = Dresden, CORS offen, ohne Schlüssel).
  Antwort: Liste mit `line`, `run` (Umlauf), `lat`/`lon`, `time` (ms seit 1970), `delayed` (Sekunden).
  Einträge älter als ca. 3 Minuten fallen serverseitig heraus. Daneben gibt es `/v1/gtfs/0` (GTFS-RT-ähnlich, JSON)
  und den Websocket `wss://socket.tlm.solutions` (Filter per JSON: `lines`, `regions`).
- **Abdeckung (Stichprobe 25.11.2026, 16:45):** rund 460 Fahrzeuge, Straßenbahn 1–13 und DVB-Stadtbusse; keine
  S-Bahn, keine Regionalbusse. Positionen kommen nur an R09-Meldepunkten (Ampeln, Haltestellen), nicht als GPS-Spur.
- **Zuordnung in der App** (`LiveVehicles.swift`): nur Straßenbahn/Stadtbus mit rein numerischer Linie und einem Halt
  im Raum Dresden. Kandidaten: gleiche Linie, höchstens 120 m neben dem Streckenverlauf. Gewählt wird das Fahrzeug,
  dessen Lage am besten zu Fahrplan/Echtzeit passt (Abstand höchstens 2 km, ähnliche Verspätung); der Umlauf
  wird danach festgehalten. Zwischen zwei Meldungen rückt der Marker mit der Fahrplan-Geschwindigkeit weiter,
  höchstens bis zum nächsten Halt. Ohne Treffer bleibt die geschätzte Position.
- **Anzeige:** Karte, Zeitleiste und „Nächster Halt“ (Fahrtdetails und Abfahrtsmonitor) nutzen die Live-Position,
  mit grünem LIVE-Schild. Für Fahrten aus der Verbindungssuche lädt die App ab 30 Minuten vor der Abfahrt jede
  Minute den ganzen Lauf der Bahn (`fullRun(of:source:)`) – so wird auch die Bahn erkannt, die noch zum Einstieg
  unterwegs ist („noch 3 Halte bis zum Einstieg“). Die Live-Aktivität nutzt TLMS nicht: Sie zeigt keine Position,
  und ohne Push-Server ließe sie sich im Hintergrund ohnehin nicht laufend nachführen.
- **Last:** abgefragt wird nur, solange eine dieser Ansichten offen ist und eine Fahrt infrage kommt – höchstens
  alle 12–15 Sekunden, gemeinsam für alle Ansichten (`LiveVehicleFeed`).
- **VVO-Störungsmeldungen** (`POST /rc`): Baustellen und Störungen je Linie (Antwort > 200 kB).

## Wagenreihung und DB-Auslastung (vorerst entfernt)

Beides war über die inoffizielle Web-Schnittstelle von bahn.de eingebaut (Commits `d869bb9`, `340b9cf`) und wurde
wieder entfernt, bis es eine offizielle Anbindung an die DB gibt. Der Code liegt in der Git-Historie:
EVA per `reiseloesung/orte/nearby`, Wagenreihung per `reisebegleitung/wagenreihung/vehicle-sequence`,
Auslastung per `reiseloesung/abfahrten` → `reiseloesung/fahrt` (`auslastungsmeldungen`).

Auslastung kommt weiter vom VVO (`Occupancy` je Halt in `/tr/trips`, `/dm`, `/dm/trip`).

**Offizielle Wege laut DB API Marketplace (geprüft 25.11.2026):**

- **Wagenreihung** gibt es nur in **RIS::Transports** – Zugang „ausschließlich Eisenbahnverkehrsunternehmen sowie
  ausgewählten Dritten …, die nachweislich in deren Auftrag handeln“, nach Prüfung und mit Vertrag; Testzugang
  2 Monate, danach Pakete „Preis auf Anfrage“. Die Endpunkte `/occupancies` dort sind nicht dokumentiert. Anfrage
  wäre über ris-api@deutschebahn.com möglich, für eine freie App aber wenig aussichtsreich.
- **Auslastung je Zug**: kein offenes Produkt. RIS::Stations kennt nur Bahnhofs-Auslastung (Pakete ab 4.200 €/Jahr),
  RIS::Boards/RIS::Journeys (Transporteure) nennen keine Auslastung und sind DB-Vertriebspartnern vorbehalten.
- **Timetables** ist nicht mehr im Katalog (Produktseite 404).
- **OpenBoards** ist offen und kostenlos (10 Anfragen/s, Bedingungen wie „Web Bahnhofstafel“): Abfahrts- und
  Ankunftstafeln der Schiene mit Gleisen, Ausfällen, Ersatzzügen und Störungstexten – aber ohne Wagenreihung und
  Auslastung. Genauer geprüft (25.11.2026), **vorerst nicht eingebaut**:
  - Zugang nur mit Marketplace-Konto und eigenem Schlüssel (`DB-Client-Id`, `DB-Api-Key`); in einer
    Open-Source-App läge der Schlüssel offen im Code bzw. in der App.
  - Es gelten die Bedingungen der „Web-Bahnhofstafel“ (db.info/bahnhof-de/nutzungsbedingungen_wbt.html):
    Verbreitung bzw. öffentliche Wiedergabe der Inhalte zu gewerblichen Zwecken und automatisierte Extraktion nur
    mit vorheriger schriftlicher Zustimmung – für eine veröffentlichte App also vorher bei
    opendata.infrago@deutschebahn.com nachfragen.
  - Transitous liefert für Züge schon Echtzeit, geplantes und aktuelles Gleis und Ausfälle (Stichprobe Dresden Hbf:
    14 von 15 Zügen mit Echtzeit und Gleis, zwei echte Gleiswechsel). Mehrwert von OpenBoards wären vor allem
    Verspätungsgründe, Störungs- und Kundentexte sowie Ersatzverkehre bei der Bahn.
  - Antwortfelder sind öffentlich nicht dokumentiert (Spec-Seite leer); ob Nicht-DB-Unternehmen enthalten sind, ist
    offen.
- **OpenBoards-Broker von Bahn-Vorhersage** (bahnvorhersage.de/open-data/open-boards, geprüft 27.11.2026):
  Privatprojekt, das OpenBoards für alle Bahnhöfe jede Minute abruft (bei ruhigen Bahnhöfen seltener) und über
  MQTT verteilt – `openboards.bahnvorhersage.de:1883`, Topics `openboards/v1/{EVA}/departures` bzw. `…/arrivals`,
  Inhalt Brotli-komprimiert, fast 1:1 das OpenBoards-Schema plus `scrapeTs`. Quellcode auf GitLab.
  **Vorerst nicht eingebaut:**
  - Derzeit **nur Fernverkehr** – S-Bahn und Regionalzüge fehlen; den Fernverkehr deckt Transitous schon ab.
  - Gleiche Lizenz wie OpenBoards (Web-Bahnhofstafel), also weiterhin schriftliche Zustimmung der DB nötig.
  - Zugangsdaten nur auf Anfrage beim Betreiber; in einer Open-Source-App lägen sie offen.
  - **Kein TLS**, Daten gingen unverschlüsselt übers Netz.
  - Gedacht für wenige, dauerhaft verbundene Abnehmer (Bandbreite sparen), nicht für eine Verbindung je iPhone;
    kurze Vorhaltezeit (ca. 10 Minuten).
  - Wieder ansehen, sobald Regionalverkehr enthalten ist – dann am ehesten über einen eigenen kleinen Server, der die
    Daten an die App weiterreicht (Verspätungsgründe, Störungstexte, Ersatzzüge der Bahn).

Fazit: Wagenreihung und Zug-Auslastung bleiben vorerst draußen.

## Störungen, Bauarbeiten und Gleiswechsel

- **VVO `/rc`** (`{"shortterm": true}`): Streckenänderungen mit Titel, HTML-Text, Gültigkeitszeiträumen und
  Linien. Abfahrten (`/dm`: `RouteChanges`) und Fahrten (`/tr/trips`: `Mot.Changes`) verweisen per ID darauf.
  Die App lädt `/rc` höchstens alle 15 Minuten und zeigt eine Meldung nur, wenn einer ihrer Zeiträume die
  Abfahrt enthält.
- **Transitous**: `alerts` an Halten und Fahrten (GTFS-RT, `headerText`, `descriptionText`, `impactPeriod`);
  Gleiswechsel über `track` (aktuell) vs. `scheduledTrack` (Plan). Der VVO liefert kein Plan-Gleis – Gleiswechsel
  sind deshalb nur bei Transitous-Daten erkennbar.

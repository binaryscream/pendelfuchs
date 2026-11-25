# Entwurf: Anfrage an TLMS (Transit Live Mapping Solutions)

**Kontakt:** hello@tlm.solutions – oder kürzer im Matrix-Raum `#tlm-solutions:matrix.org`
(beides laut <https://github.com/tlm-solutions>). Für Matrix steht unten eine kurze englische Fassung.

---

## E-Mail (Deutsch)

**Betreff:** Live-Positionen von TLMS in einer Open-Source-Fahrplan-App (Fahrplan XL) – ist das okay?

Hallo TLMS-Team,

ich entwickle die freie, nicht-kommerzielle iOS-App „Fahrplan XL“ (Lizenz GPL-3.0, Quelltext auf GitHub, derzeit
noch privat, die Veröffentlichung ist geplant). Die App zeigt Abfahrten, Verbindungen, Widgets und
Live-Aktivitäten – kostenlos, ohne Werbung und ohne Tracking.

Für Straßenbahnen und Stadtbusse in Dresden nutze ich seit Kurzem eure Live-Positionen, und das funktioniert
richtig gut: Auf der Karte, in der Zeitleiste einer Fahrt und bei „Nächster Halt“ zeigt die App dann die gemeldete
Position statt einer Schätzung aus dem Fahrplan – inklusive der Bahn, die gerade zur eigenen Haltestelle unterwegs
ist. Danke für das tolle Projekt!

So nutze ich die Daten:

- Abfrage: `GET https://lizard.tlm.solutions/v1/vehicles/0`
- nur, solange in der App eine Karte oder Fahrtansicht offen ist **und** die Fahrt eine Dresdner Straßenbahn oder
  ein Stadtbus ist – dann höchstens alle 12–15 Sekunden, gemeinsam für alle offenen Ansichten
- kein eigener Server, keine Speicherung, keine Weitergabe; die Abfrage geht direkt vom iPhone an euch
- Quellenangabe in der App: „Live: TLMS“ mit Link auf tlm.solutions (auf der Karte und in den Einstellungen)

Dazu ein paar Fragen:

1. Ist es für euch in Ordnung, wenn die App eure Daten so nutzt – auch wenn sie später im App Store erscheint?
   Falls ihr Bedingungen habt (Quellenangabe, Lizenz der Daten, Kennzeichnung der App), halte ich mich gern daran.
2. Ist `lizard.tlm.solutions/v1/vehicles/0` die richtige Schnittstelle dafür, oder wäre euch etwas anderes lieber,
   z. B. der Websocket (`socket.tlm.solutions`) mit Filter auf einzelne Linien? Gibt es eine Obergrenze für
   Anfragen, die ich beachten sollte?
3. Ihr schreibt, dass das Projekt weitgehend abgeschlossen ist und nur noch gelegentlich betreut wird. Kann ich
   davon ausgehen, dass die Schnittstelle erst einmal weiterläuft? Die App fällt ohne Daten einfach auf die
   Schätzung zurück, es geht also nichts kaputt – ich möchte nur nichts versprechen, was nicht stimmt.
4. Wenn euch in der App etwas auffällt oder ihr etwas anders dargestellt haben möchtet, sagt gern Bescheid.

Vielen Dank und viele Grüße
[Name]
[Kontakt / Link zum Projekt]

---

## Matrix (Englisch, kurz)

Hi! I'm building Fahrplan XL, a free, non-commercial, open-source (GPL-3.0) iOS transit app. For trams and city
buses in Dresden it now shows your live positions on the map and in the trip timeline – works great, thanks for
building this!

Usage: `GET lizard.tlm.solutions/v1/vehicles/0`, only while a map or trip view is open and the trip is a Dresden
tram/city bus, at most every 12–15 s, straight from the phone (no server, nothing stored). The app credits
“Live: TLMS” with a link to tlm.solutions.

Is that okay with you, also once the app is on the App Store? Would you prefer a different endpoint (e.g. the
websocket with a line filter) or a request limit? And is it fine to assume the API keeps running for now? The app
falls back to schedule-based estimates if it doesn't. Thanks!

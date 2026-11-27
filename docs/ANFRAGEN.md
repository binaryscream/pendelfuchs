# Anfragen an die Datenquellen – zum Kopieren

Stand 27.11.2026. Jeder Block ist fertig: Empfänger, Betreff und Text kopieren, abschicken.
Absender ist die E-Mail-Adresse, von der du schreibst – sie steht deshalb nicht im Text.

> **Versendet am 27.11.2026:** VVO und TLMS per E-Mail, Transitous im Matrix-Raum, außerdem alle sechs Anfragen an die
> regionalen Verbünde (Abschnitt 4: VMS, VVV, Bayern-Fahrplan, NVBW, mobil.nrw, MV-Fahrplan) per E-Mail aus Proton Mail.
>
> **Antwort Transitous (27.11.2026):** `refresh-itinerary` statt wiederholter `/plan`-Anfragen nutzen, alles über
> v6. Umgesetzt (siehe `docs/DATENQUELLEN.md`). Antworten von VVO, TLMS und den regionalen Verbünden stehen noch aus.

| Stelle | Wofür die App sie nutzt | Anfrage nötig? | Kanal |
|---|---|---|---|
| VVO | Abfahrten, Verbindungen, Preise, Auslastung im VVO-Gebiet | **Ja** – Schnittstelle ist inoffiziell | E-Mail |
| TLMS | Live-Positionen von Straßenbahn und Stadtbus in Dresden | **Ja** – keine Nutzungsbedingungen veröffentlicht | E-Mail oder Matrix |
| Transitous | Fahrplandaten für ganz Deutschland | **Ja, als Absprache** – Bedingungen verlangen das bei vielen Nutzern | Matrix |
| OpenFreeMap | Kartenkacheln | Nein – frei nutzbar, Grenzen gelten nur für Offline-Downloads (macht die App nicht) | – |
| Regionale Verbünde (VMS, VVV, Bayern-Fahrplan, NVBW, mobil.nrw, MV-Fahrplan) | Abfahrten, Verbindungen, Echtzeit, teils Preise in ihrer Region | **Ja** – keine Nutzungsbedingungen veröffentlicht | E-Mail (Abschnitt 4) |
| Deutsche Bahn | – | Nein – wird nicht genutzt | – |

---

## 1. VVO (Verkehrsverbund Oberelbe)

**An:** opendata@vvo-online.de
**Falls die Adresse nicht zustellbar ist:** service@vvo-online.de (mit der Bitte um Weiterleitung an die Open-Data-Ansprechpartner)
**Betreff:** Nutzung der VVO-Schnittstellen in einer kostenlosen Open-Source-Fahrplan-App (Pendelfuchs)

```
Guten Tag,

ich entwickle die kostenlose iOS-App „Pendelfuchs“ – eine Fahrplan-App ohne Werbung, ohne Tracking und ohne Nutzerkonto. Der Quelltext steht unter der Open-Source-Lizenz GPL-3.0; er liegt derzeit noch privat auf GitHub und wird vor der Veröffentlichung im App Store freigegeben.

Die App zeigt Abfahrten, Verbindungen mit Echtzeit, Widgets und Live-Aktivitäten für regelmäßige Fahrten. Im Gebiet des VVO nutzt sie dafür bisher die WebAPI unter webapi.vvo-online.de, und zwar diese Funktionen:
- /dm (Abfahrten einer Haltestelle)
- /dm/trip (Fahrtverlauf)
- /tr/trips (Verbindungssuche)
- /tr/pointfinder (Haltestellensuche)
- /rc (Störungen und Baustellen, zwischengespeichert und in der Regel höchstens alle 15 Minuten)

Außerhalb des Verbundgebiets kommen die Daten von Transitous. Die App fragt direkt vom iPhone aus ab, es gibt keinen eigenen Server und nichts wird gespeichert oder weitergegeben. Abgefragt wird nur bei Bedarf: wenn jemand die App öffnet, wenn ein Widget aktualisiert wird oder kurz vor einer gemerkten Fahrt.

Mir ist bewusst, dass die WebAPI nicht offiziell dokumentiert ist. Bevor die App erscheint, möchte ich deshalb Ihr Einverständnis einholen. Dazu habe ich vier Fragen:

1. Darf die App die WebAPI in diesem Umfang nutzen? Falls Sie Bedingungen haben – etwa eine Quellenangabe, eine Obergrenze für Anfragen oder eine Kennung im Header –, setze ich sie gern um.
2. Gibt es eine offizielle Schnittstelle, die Ihnen lieber wäre, zum Beispiel TRIAS? Dann würde ich die App darauf umstellen.
3. Mit wie vielen Anfragen sollte ich höchstens rechnen, damit Ihre Systeme nicht belastet werden?
4. Darf die App „Daten: VVO“ als Quelle anzeigen? So steht es bisher in der App.

Wenn Sie die Nutzung nicht wünschen, ist das auch in Ordnung – dann nutzt die App im VVO-Gebiet nur die Daten von Transitous.

Vielen Dank und freundliche Grüße
Rico Kullmann
Heidenau
```

---

## 2. TLMS (Transit Live Mapping Solutions)

**An:** hello@tlm.solutions
**Oder im Matrix-Raum:** `#dump-dvb:matrix.org` (so auf tlm.solutions verlinkt) – dafür die kurze englische Fassung unten.
**Betreff:** Live-Positionen von TLMS in einer kostenlosen Open-Source-Fahrplan-App (Pendelfuchs) – ist das okay?

```
Hallo TLMS-Team,

ich entwickle die kostenlose iOS-App „Pendelfuchs“ – eine Fahrplan-App ohne Werbung, ohne Tracking und ohne Nutzerkonto. Der Quelltext steht unter GPL-3.0; er liegt derzeit noch privat auf GitHub und wird vor der Veröffentlichung im App Store freigegeben.

Für Straßenbahnen und Stadtbusse in Dresden nutze ich eure Live-Positionen, und das funktioniert richtig gut: Auf der Karte, in der Zeitleiste einer Fahrt und bei „Nächster Halt“ zeigt die App die gemeldete Position statt einer Schätzung aus dem Fahrplan – auch für die Bahn, die gerade zur eigenen Haltestelle unterwegs ist. Danke für das tolle Projekt!

So nutze ich die Daten:
- Abfrage: GET https://lizard.tlm.solutions/v1/vehicles/0
- nur, solange in der App eine Karte oder Fahrtansicht offen ist und die Fahrt eine Dresdner Straßenbahn oder ein Stadtbus ist – dann höchstens alle 12 bis 15 Sekunden, gemeinsam für alle offenen Ansichten
- kein eigener Server, keine Speicherung, keine Weitergabe; die Abfrage geht direkt vom iPhone an euch
- Quellenangabe in der App: „Live-Fahrzeuge Dresden: TLMS“ mit Link auf tlm.solutions

Dazu ein paar Fragen:

1. Ist es für euch in Ordnung, wenn die App eure Daten so nutzt – auch wenn sie im App Store erscheint? Falls ihr Bedingungen habt (Quellenangabe, Lizenz der Daten, Kennzeichnung), halte ich mich gern daran.
2. Ist /v1/vehicles/0 die richtige Schnittstelle, oder wäre euch der Websocket mit Filter auf einzelne Linien lieber? Gibt es eine Obergrenze für Anfragen?
3. Kann ich davon ausgehen, dass die Schnittstelle erst einmal weiterläuft? Ohne Daten fällt die App einfach auf die Schätzung zurück, es geht also nichts kaputt – ich möchte nur nichts versprechen, was nicht stimmt.
4. Wenn euch in der App etwas auffällt oder ihr etwas anders dargestellt haben möchtet, sagt gern Bescheid.

Vielen Dank und viele Grüße
Rico Kullmann
Heidenau
```

**Kurzfassung für Matrix (Englisch):**

```
Hi! I'm building Pendelfuchs, a free, open-source (GPL-3.0) iOS transit app without ads, tracking or accounts. For trams and city buses in Dresden it shows your live positions on the map and in the trip timeline – works great, thanks for building this!

Usage: GET lizard.tlm.solutions/v1/vehicles/0, only while a map or trip view is open and the trip is a Dresden tram or city bus, at most every 12–15 s, straight from the phone (no server, nothing stored). The app credits "TLMS" with a link to tlm.solutions.

Is that okay with you, also once the app is on the App Store? Would you prefer the websocket with a line filter, or is there a request limit I should respect? And is it fine to assume the API keeps running for now? If it doesn't, the app simply falls back to schedule-based estimates. Thanks!
```

---

## 3. Transitous

**Wo:** Matrix-Raum `#transitous:matrix.spline.de` (Link: https://matrix.to/#/#transitous:matrix.spline.de)
**Warum:** Die Bedingungen auf transitous.org/api bitten darum, sich abzustimmen, wenn eine App viele Nutzer, viele Verbindungssuchen (/plan) oder automatische Anfragen hat. Widgets und Hintergrundprüfungen sind automatische Anfragen.

```
Hi Transitous team! I'm building Pendelfuchs, a free iOS transit app without ads, tracking or accounts, licensed GPL-3.0. The source is still private on GitHub and will be published before the App Store release. It uses the MOTIS 2 API for all of Germany; inside the VVO area (Dresden region) it uses the VVO's own API instead, so most of my own test traffic doesn't hit you.

Before publishing I'd like to check the expected load with you, since the app makes some automated requests:
- /v1/geocode, /v5/stoptimes and /v5/plan, straight from the phone (no backend, nothing stored)
- /v5/plan also runs without user interaction: home-screen widgets (iOS reloads them roughly every 15 minutes at best, usually less often), background checks for saved regular trips (from one hour before departure, when iOS wakes the app, typically every 15 minutes or less), and a refresh every 45 s while a trip detail screen is open
- my rough guess is a few dozen /plan requests per active user per day, more for someone with a route widget
- the User-Agent will be "Pendelfuchs/<version> (+<contact URL>)", and the app links to transitous.org/sources and credits OpenStreetMap

Is that okay? Is there a per-user or total volume I should stay under, or anything you'd like me to change (e.g. fewer widget refreshes, caching, different endpoints)? I don't know the number of users yet; it starts as a small hobby project. Thanks for running this!
```

---

## 4. Regionale Verbünde (über TripKit)

Die App fragt in diesen Regionen zusätzlich die Fahrplanauskunft des Verbunds ab (EFA-Schnittstellen, eingebunden über
die Open-Source-Bibliothek TripKit, siehe `docs/DATENQUELLEN.md`). Offizielle Nutzungsbedingungen für diese Adressen sind
nicht veröffentlicht – deshalb vor dem Hochladen fragen. **Wer nein sagt oder nicht antwortet:** den Verbund in
`RegionalNetwork` streichen (bzw. alle mit `useRegional: false` im Router abschalten); dann übernimmt Transitous.

Die Adressen sind recherchiert (Stand 27.11.2026), meist allgemeine Kontaktadressen – die Bitte um Weiterleitung
steht deshalb in jedem Text.

### 4.1 VMS (Verkehrsverbund Mittelsachsen)

**An:** info@vms.de
**Hinweis:** Laut Impressum die Adresse des VMS (geprüft 27.11.2026). Der Bereich „Open Data – GTFS-Daten“ unter vms.de → Service → Downloads nennt keinen eigenen Ansprechpartner. Dort gibt es nur Solldaten als GTFS (wöchentlich, CC BY 4.0, Quellenangabe „VMS GmbH“) – keine Echtzeit, deshalb bleibt die Anfrage zur Fahrplanauskunft nötig.
**Betreff:** Nutzung Ihrer Fahrplanauskunft in einer kostenlosen Open-Source-Fahrplan-App (Pendelfuchs)

```
Guten Tag,

ich entwickle die kostenlose iOS-App „Pendelfuchs“ – eine Fahrplan-App ohne Werbung, ohne Tracking und ohne Nutzerkonto. Der Quelltext steht unter der Open-Source-Lizenz GPL-3.0 und wird vor der Veröffentlichung im App Store freigegeben. Falls Sie nicht die richtige Stelle sind, leiten Sie meine Anfrage bitte an die zuständigen Ansprechpartner für Fahrplandaten weiter – vielen Dank!

Die App zeigt Abfahrten, Verbindungen mit Echtzeit, Widgets und Live-Aktivitäten für regelmäßige Fahrten. Grundlage für ganz Deutschland sind die offenen Daten von Transitous. Für Chemnitz, Zwickau, Erzgebirge und Mittelsachsen fragt die App zusätzlich Ihre Fahrplanauskunft ab, weil sie dort oft genauere Echtzeitdaten hat. Genutzt wird die EFA-Schnittstelle unter
https://efa.vms.de/VMSSL3/
mit diesen Abfragen: Haltestellensuche, Abfahrten einer Haltestelle, Verbindungssuche und Fahrtverlauf. Angebunden ist sie über die freie Bibliothek TripKit, die auch andere Fahrplan-Apps verwenden.

Die App fragt direkt vom iPhone aus ab, es gibt keinen eigenen Server, und nichts wird gespeichert oder weitergegeben. Abgefragt wird nur bei Bedarf: wenn jemand in der App sucht, wenn ein Widget aktualisiert wird oder kurz vor einer gemerkten Fahrt. Ist Ihre Auskunft nicht erreichbar, nutzt die App automatisch nur Transitous.

Ihre GTFS-Daten unter CC BY 4.0 kenne ich; da sie keine Echtzeit enthalten, würde ich für die aktuellen Abfahrten gern Ihre Fahrplanauskunft nutzen. Bevor die App erscheint, möchte ich Ihr Einverständnis einholen. Dazu habe ich vier Fragen:

1. Darf die App Ihre Fahrplanauskunft in diesem Umfang nutzen? Falls Sie Bedingungen haben – etwa eine Quellenangabe, eine Obergrenze für Anfragen oder eine Kennung im Header –, setze ich sie gern um.
2. Gibt es eine offizielle Schnittstelle, die Ihnen lieber wäre (zum Beispiel TRIAS)? Dann würde ich die App darauf umstellen.
3. Mit wie vielen Anfragen sollte ich höchstens rechnen, damit Ihre Systeme nicht belastet werden?
4. Darf die App „Daten: VMS“ als Quelle anzeigen?

Wenn Sie die Nutzung nicht wünschen, ist das auch in Ordnung – dann nutzt die App in Ihrem Gebiet nur die Daten von Transitous.

Vielen Dank und freundliche Grüße
Rico Kullmann
Heidenau
```

### 4.2 VVV (Verkehrsverbund Vogtland)

**An:** mail@vvvogtland.de
**Hinweis:** Allgemeine Adresse aus den Nutzungsbedingungen und dem App-Store-Eintrag des VVV.
**Betreff:** Nutzung Ihrer Fahrplanauskunft in einer kostenlosen Open-Source-Fahrplan-App (Pendelfuchs)

```
Guten Tag,

ich entwickle die kostenlose iOS-App „Pendelfuchs“ – eine Fahrplan-App ohne Werbung, ohne Tracking und ohne Nutzerkonto. Der Quelltext steht unter der Open-Source-Lizenz GPL-3.0 und wird vor der Veröffentlichung im App Store freigegeben. Falls Sie nicht die richtige Stelle sind, leiten Sie meine Anfrage bitte an die zuständigen Ansprechpartner für Fahrplandaten weiter – vielen Dank!

Die App zeigt Abfahrten, Verbindungen mit Echtzeit, Widgets und Live-Aktivitäten für regelmäßige Fahrten. Grundlage für ganz Deutschland sind die offenen Daten von Transitous. Für Vogtlandkreis fragt die App zusätzlich Ihre Fahrplanauskunft ab, weil sie dort oft genauere Echtzeitdaten hat. Genutzt wird die EFA-Schnittstelle unter
https://vogtlandauskunft.de/vvv2/
mit diesen Abfragen: Haltestellensuche, Abfahrten einer Haltestelle, Verbindungssuche und Fahrtverlauf. Angebunden ist sie über die freie Bibliothek TripKit, die auch andere Fahrplan-Apps verwenden.

Die App fragt direkt vom iPhone aus ab, es gibt keinen eigenen Server, und nichts wird gespeichert oder weitergegeben. Abgefragt wird nur bei Bedarf: wenn jemand in der App sucht, wenn ein Widget aktualisiert wird oder kurz vor einer gemerkten Fahrt. Ist Ihre Auskunft nicht erreichbar, nutzt die App automatisch nur Transitous.

Bevor die App erscheint, möchte ich Ihr Einverständnis einholen. Dazu habe ich vier Fragen:

1. Darf die App Ihre Fahrplanauskunft in diesem Umfang nutzen? Falls Sie Bedingungen haben – etwa eine Quellenangabe, eine Obergrenze für Anfragen oder eine Kennung im Header –, setze ich sie gern um.
2. Gibt es eine offizielle Schnittstelle, die Ihnen lieber wäre (zum Beispiel TRIAS)? Dann würde ich die App darauf umstellen.
3. Mit wie vielen Anfragen sollte ich höchstens rechnen, damit Ihre Systeme nicht belastet werden?
4. Darf die App „Daten: VVV“ als Quelle anzeigen?

Wenn Sie die Nutzung nicht wünschen, ist das auch in Ordnung – dann nutzt die App in Ihrem Gebiet nur die Daten von Transitous.

Vielen Dank und freundliche Grüße
Rico Kullmann
Heidenau
```

### 4.3 Bayern-Fahrplan (Bayerische Eisenbahngesellschaft)

**An:** info@bahnland-bayern.de
**Hinweis:** Adresse laut Impressum auf bahnland-bayern.de (geprüft 27.11.2026). Die BEG betreibt DEFAS bzw. den Bayern-Fahrplan. Laut bayerninfo.de gibt es Echtzeit offiziell nur über TRIAS mit Vertrag – Frage 2 zielt darauf.
**Betreff:** Nutzung Ihrer Fahrplanauskunft in einer kostenlosen Open-Source-Fahrplan-App (Pendelfuchs)

```
Guten Tag,

ich entwickle die kostenlose iOS-App „Pendelfuchs“ – eine Fahrplan-App ohne Werbung, ohne Tracking und ohne Nutzerkonto. Der Quelltext steht unter der Open-Source-Lizenz GPL-3.0 und wird vor der Veröffentlichung im App Store freigegeben. Falls Sie nicht die richtige Stelle sind, leiten Sie meine Anfrage bitte an die zuständigen Ansprechpartner für Fahrplandaten weiter – vielen Dank!

Die App zeigt Abfahrten, Verbindungen mit Echtzeit, Widgets und Live-Aktivitäten für regelmäßige Fahrten. Grundlage für ganz Deutschland sind die offenen Daten von Transitous. Für Bayern fragt die App zusätzlich Ihre Fahrplanauskunft ab, weil sie dort oft genauere Echtzeitdaten hat. Genutzt wird die EFA-Schnittstelle unter
https://mobile.defas-fgi.de/beg/
mit diesen Abfragen: Haltestellensuche, Abfahrten einer Haltestelle, Verbindungssuche und Fahrtverlauf. Angebunden ist sie über die freie Bibliothek TripKit, die auch andere Fahrplan-Apps verwenden.

Die App fragt direkt vom iPhone aus ab, es gibt keinen eigenen Server, und nichts wird gespeichert oder weitergegeben. Abgefragt wird nur bei Bedarf: wenn jemand in der App sucht, wenn ein Widget aktualisiert wird oder kurz vor einer gemerkten Fahrt. Ist Ihre Auskunft nicht erreichbar, nutzt die App automatisch nur Transitous.

Bevor die App erscheint, möchte ich Ihr Einverständnis einholen. Dazu habe ich vier Fragen:

1. Darf die App Ihre Fahrplanauskunft in diesem Umfang nutzen? Falls Sie Bedingungen haben – etwa eine Quellenangabe, eine Obergrenze für Anfragen oder eine Kennung im Header –, setze ich sie gern um.
2. Gibt es eine offizielle Schnittstelle, die Ihnen lieber wäre (zum Beispiel TRIAS)? Dann würde ich die App darauf umstellen.
3. Mit wie vielen Anfragen sollte ich höchstens rechnen, damit Ihre Systeme nicht belastet werden?
4. Darf die App „Daten: Bayern-Fahrplan“ als Quelle anzeigen?

Wenn Sie die Nutzung nicht wünschen, ist das auch in Ordnung – dann nutzt die App in Ihrem Gebiet nur die Daten von Transitous.

Vielen Dank und freundliche Grüße
Rico Kullmann
Heidenau
```

### 4.4 NVBW (Baden-Württemberg)

**An:** mobidata-bw@nvbw.de
**Hinweis:** Adresse von MobiData BW, der Open-Data-Plattform der NVBW. Die NVBW bietet die EFA-BW offiziell und kostenlos als TRIAS-Schnittstelle über MobiData BW an (mit Nutzungsbedingungen) – gut möglich, dass sie darauf verweist.
**Betreff:** Nutzung Ihrer Fahrplanauskunft in einer kostenlosen Open-Source-Fahrplan-App (Pendelfuchs)

```
Guten Tag,

ich entwickle die kostenlose iOS-App „Pendelfuchs“ – eine Fahrplan-App ohne Werbung, ohne Tracking und ohne Nutzerkonto. Der Quelltext steht unter der Open-Source-Lizenz GPL-3.0 und wird vor der Veröffentlichung im App Store freigegeben. Falls Sie nicht die richtige Stelle sind, leiten Sie meine Anfrage bitte an die zuständigen Ansprechpartner für Fahrplandaten weiter – vielen Dank!

Die App zeigt Abfahrten, Verbindungen mit Echtzeit, Widgets und Live-Aktivitäten für regelmäßige Fahrten. Grundlage für ganz Deutschland sind die offenen Daten von Transitous. Für Baden-Württemberg fragt die App zusätzlich Ihre Fahrplanauskunft ab, weil sie dort oft genauere Echtzeitdaten hat. Genutzt wird die EFA-Schnittstelle unter
https://www.efa-bw.de/nvbw/
mit diesen Abfragen: Haltestellensuche, Abfahrten einer Haltestelle, Verbindungssuche und Fahrtverlauf. Angebunden ist sie über die freie Bibliothek TripKit, die auch andere Fahrplan-Apps verwenden.

Die App fragt direkt vom iPhone aus ab, es gibt keinen eigenen Server, und nichts wird gespeichert oder weitergegeben. Abgefragt wird nur bei Bedarf: wenn jemand in der App sucht, wenn ein Widget aktualisiert wird oder kurz vor einer gemerkten Fahrt. Ist Ihre Auskunft nicht erreichbar, nutzt die App automatisch nur Transitous.

Mir ist bekannt, dass Sie die EFA-BW über MobiData BW auch als TRIAS-Schnittstelle anbieten. Bevor die App erscheint, möchte ich Ihr Einverständnis einholen. Dazu habe ich vier Fragen:

1. Darf die App Ihre Fahrplanauskunft in diesem Umfang nutzen? Falls Sie Bedingungen haben – etwa eine Quellenangabe, eine Obergrenze für Anfragen oder eine Kennung im Header –, setze ich sie gern um.
2. Gibt es eine offizielle Schnittstelle, die Ihnen lieber wäre (zum Beispiel TRIAS)? Dann würde ich die App darauf umstellen.
3. Mit wie vielen Anfragen sollte ich höchstens rechnen, damit Ihre Systeme nicht belastet werden?
4. Darf die App „Daten: NVBW“ als Quelle anzeigen?

Wenn Sie die Nutzung nicht wünschen, ist das auch in Ordnung – dann nutzt die App in Ihrem Gebiet nur die Daten von Transitous.

Vielen Dank und freundliche Grüße
Rico Kullmann
Heidenau
```

### 4.5 mobil.nrw (Nordrhein-Westfalen)

**An:** mdd-nrw@vrs.de
**Hinweis:** Adresse der Multimodalen Datendrehscheibe NRW (beim VRS), die die landesweiten Fahrplandaten bereitstellt. Für mobil.nrw selbst ist keine technische Adresse veröffentlicht; die Bitte um Weiterleitung steht deshalb im Text.
**Betreff:** Nutzung Ihrer Fahrplanauskunft in einer kostenlosen Open-Source-Fahrplan-App (Pendelfuchs)

```
Guten Tag,

ich entwickle die kostenlose iOS-App „Pendelfuchs“ – eine Fahrplan-App ohne Werbung, ohne Tracking und ohne Nutzerkonto. Der Quelltext steht unter der Open-Source-Lizenz GPL-3.0 und wird vor der Veröffentlichung im App Store freigegeben. Falls Sie nicht die richtige Stelle sind, leiten Sie meine Anfrage bitte an die zuständigen Ansprechpartner für Fahrplandaten weiter – vielen Dank!

Die App zeigt Abfahrten, Verbindungen mit Echtzeit, Widgets und Live-Aktivitäten für regelmäßige Fahrten. Grundlage für ganz Deutschland sind die offenen Daten von Transitous. Für Nordrhein-Westfalen fragt die App zusätzlich Ihre Fahrplanauskunft ab, weil sie dort oft genauere Echtzeitdaten hat. Genutzt wird die EFA-Schnittstelle unter
https://ticketshop.mobil.nrw/MS_EFA/
mit diesen Abfragen: Haltestellensuche, Abfahrten einer Haltestelle, Verbindungssuche und Fahrtverlauf. Angebunden ist sie über die freie Bibliothek TripKit, die auch andere Fahrplan-Apps verwenden.

Die App fragt direkt vom iPhone aus ab, es gibt keinen eigenen Server, und nichts wird gespeichert oder weitergegeben. Abgefragt wird nur bei Bedarf: wenn jemand in der App sucht, wenn ein Widget aktualisiert wird oder kurz vor einer gemerkten Fahrt. Ist Ihre Auskunft nicht erreichbar, nutzt die App automatisch nur Transitous.

Bevor die App erscheint, möchte ich Ihr Einverständnis einholen. Dazu habe ich vier Fragen:

1. Darf die App Ihre Fahrplanauskunft in diesem Umfang nutzen? Falls Sie Bedingungen haben – etwa eine Quellenangabe, eine Obergrenze für Anfragen oder eine Kennung im Header –, setze ich sie gern um.
2. Gibt es eine offizielle Schnittstelle, die Ihnen lieber wäre (zum Beispiel TRIAS)? Dann würde ich die App darauf umstellen.
3. Mit wie vielen Anfragen sollte ich höchstens rechnen, damit Ihre Systeme nicht belastet werden?
4. Darf die App „Daten: mobil.nrw“ als Quelle anzeigen?

Wenn Sie die Nutzung nicht wünschen, ist das auch in Ordnung – dann nutzt die App in Ihrem Gebiet nur die Daten von Transitous.

Vielen Dank und freundliche Grüße
Rico Kullmann
Heidenau
```

### 4.6 MV-Fahrplan (Verkehrsgesellschaft Mecklenburg-Vorpommern)

**An:** info@vmv-mbh.de
**Hinweis:** Allgemeine Adresse aus der Datenschutzerklärung der VMV. Die VMV betreibt die landesweite Auskunft; für die Fahrplandaten selbst verweist sie auf die Verkehrsunternehmen.
**Betreff:** Nutzung Ihrer Fahrplanauskunft in einer kostenlosen Open-Source-Fahrplan-App (Pendelfuchs)

```
Guten Tag,

ich entwickle die kostenlose iOS-App „Pendelfuchs“ – eine Fahrplan-App ohne Werbung, ohne Tracking und ohne Nutzerkonto. Der Quelltext steht unter der Open-Source-Lizenz GPL-3.0 und wird vor der Veröffentlichung im App Store freigegeben. Falls Sie nicht die richtige Stelle sind, leiten Sie meine Anfrage bitte an die zuständigen Ansprechpartner für Fahrplandaten weiter – vielen Dank!

Die App zeigt Abfahrten, Verbindungen mit Echtzeit, Widgets und Live-Aktivitäten für regelmäßige Fahrten. Grundlage für ganz Deutschland sind die offenen Daten von Transitous. Für Mecklenburg-Vorpommern fragt die App zusätzlich Ihre Fahrplanauskunft ab, weil sie dort oft genauere Echtzeitdaten hat. Genutzt wird die EFA-Schnittstelle unter
https://www.fahrplanauskunft-mv.de/vmv-efa/
mit diesen Abfragen: Haltestellensuche, Abfahrten einer Haltestelle, Verbindungssuche und Fahrtverlauf. Angebunden ist sie über die freie Bibliothek TripKit, die auch andere Fahrplan-Apps verwenden.

Die App fragt direkt vom iPhone aus ab, es gibt keinen eigenen Server, und nichts wird gespeichert oder weitergegeben. Abgefragt wird nur bei Bedarf: wenn jemand in der App sucht, wenn ein Widget aktualisiert wird oder kurz vor einer gemerkten Fahrt. Ist Ihre Auskunft nicht erreichbar, nutzt die App automatisch nur Transitous.

Bevor die App erscheint, möchte ich Ihr Einverständnis einholen. Dazu habe ich vier Fragen:

1. Darf die App Ihre Fahrplanauskunft in diesem Umfang nutzen? Falls Sie Bedingungen haben – etwa eine Quellenangabe, eine Obergrenze für Anfragen oder eine Kennung im Header –, setze ich sie gern um.
2. Gibt es eine offizielle Schnittstelle, die Ihnen lieber wäre (zum Beispiel TRIAS)? Dann würde ich die App darauf umstellen.
3. Mit wie vielen Anfragen sollte ich höchstens rechnen, damit Ihre Systeme nicht belastet werden?
4. Darf die App „Daten: MV-Fahrplan“ als Quelle anzeigen?

Wenn Sie die Nutzung nicht wünschen, ist das auch in Ordnung – dann nutzt die App in Ihrem Gebiet nur die Daten von Transitous.

Vielen Dank und freundliche Grüße
Rico Kullmann
Heidenau
```

---

## Nach den Antworten

- **VVO sagt nein oder antwortet nicht:** Den VVO im Code abschalten (`vvo: nil` in `DataSources.router`), dann läuft das VVO-Gebiet über Transitous.
- **Ein regionaler Verbund sagt nein oder antwortet nicht:** ihn aus `RegionalNetwork` streichen; Transitous übernimmt.
- **TLMS sagt nein:** Live-Positionen abschalten; die App zeigt dann nur die geschätzte Position.
- **Transitous nennt Grenzen:** Widget- und Hintergrundabfragen entsprechend drosseln.
- **Kontakt-URL im User-Agent** zeigt noch auf das private GitHub-Repo. Sobald die Website online ist, auf deren Adresse umstellen (`TransitousProvider.contactURL`).

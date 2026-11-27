# App-Store-Eintrag – zum Kopieren in App Store Connect

Stand 27.11.2026. Alles auf Deutsch, Sprache des Eintrags: **Deutsch**. Die Zeichengrenzen sind geprüft
(Zahlen in Klammern). Die Website `https://pendelfuchs.de` ist online (27.11.2026).

## App anlegen (einmalig)

| Feld | Wert |
|---|---|
| Plattform | iOS |
| Name | **Pendelfuchs** |
| Primäre Sprache | Deutsch |
| Bundle-ID | `de.pendelfuchs.app` |
| SKU | `pendelfuchs-ios` (frei wählbar, nur für dich sichtbar) |
| Benutzerzugriff | Uneingeschränkt |

## Produktseite

**Name** (11/30)
```
Pendelfuchs
```

**Untertitel** (25/30)
```
Fahrplan für Bus und Bahn
```

**Werbetext** (166/170; in App Store Connect „Promotional Text“, jederzeit ohne Update änderbar)
```
Abfahrten, Verbindungen und Live-Aktivität für deine tägliche Strecke – mit Erinnerung vor der Abfahrt und Ersatz bei Ausfall. Kostenlos, ohne Werbung, ohne Tracking.
```

**Suchbegriffe** (99/100 Byte – Umlaute zählen doppelt; Wörter aus Name und Untertitel nicht wiederholen)
```
ÖPNV,Abfahrt,Verbindung,S-Bahn,Straßenbahn,Tram,Zug,Pendler,Echtzeit,Deutschlandticket,Widget,VVO
```

**Beschreibung** (2327/4000)
```
Pendelfuchs ist eine Fahrplan-App für alle, die regelmäßig mit Bus und Bahn unterwegs sind. Merk dir deine tägliche Strecke einmal – den Rest erledigt die App.

ABFAHRTEN
• Haltestellen in der Nähe, Favoriten und zuletzt verwendete Haltestellen auf einen Blick
• Echtzeit mit Verspätungen, Ausfällen und Gleiswechseln
• Filter nach Linie und Richtung
• Fahrtverlauf mit allen Halten

VERBINDUNGEN
• Von – Nach – über, mit Abfahrts- oder Ankunftszeit
• Suchoptionen: nur Deutschlandticket, höchstens ein Umstieg, Gehgeschwindigkeit, Verkehrsmittel
• Zuletzt gesuchte Strecken mit einem Tipp erneut suchen
• Karte mit Streckenverlauf und Fahrzeugposition – in Dresden für Straßenbahn und Stadtbus sogar live

MEINE FAHRTEN
• Verbindung merken und Wochentage wählen – fertig ist die regelmäßige Fahrt
• Verpass-Assistent: Fällt deine Bahn aus oder ist ein Anschluss nicht mehr zu schaffen, zeigt die App gleich die nächste passende Verbindung
• Erinnerung vor der Abfahrt, mit Knopf zum Starten der Live-Aktivität
• Meldungen bei Ausfall, Verspätung, Gleiswechsel und knappen Anschlüssen

LIVE-AKTIVITÄT
• Countdown bis zur Abfahrt und zum Ausstieg auf dem Sperrbildschirm und in der Dynamic Island
• Umstiege mit Zeiten auf einen Blick

WIDGETS
• Abfahrten an deiner Haltestelle
• Strecke von A nach B, ab einer Uhrzeit automatisch mit Rückweg
• Meine nächste Fahrt – mit Knopf für die Live-Aktivität

SIRI UND KURZBEFEHLE
• „Abfahrten in Pendelfuchs“, „Wie fährt meine Fahrt in Pendelfuchs“, „Verbindung nach … in Pendelfuchs“

DATENSCHUTZ
Kein Konto, keine Werbung, kein Tracking. Favoriten und gemerkte Fahrten bleiben auf deinem iPhone. Pendelfuchs hat keinen eigenen Server – die App fragt die Fahrplandienste direkt ab.

GUT ZU WISSEN
Weil es keinen eigenen Server gibt, holt die App neue Echtzeitdaten, solange sie offen ist und wenn iOS sie im Hintergrund kurz weckt. Benachrichtigungen können deshalb etwas später kommen; die Erinnerung vor der Abfahrt ist fest eingeplant und kommt pünktlich.

DATENQUELLEN
Fahrplandaten für ganz Deutschland von Transitous (u. a. DELFI e. V., CC BY 4.0), im Gebiet des Verkehrsverbunds Oberelbe zusätzlich vom VVO, in weiteren Regionen von den Verbünden VMS, VVV, Bayern-Fahrplan, NVBW, mobil.nrw und MV-Fahrplan. Live-Fahrzeuge in Dresden von TLMS. Karten von OpenFreeMap, © OpenMapTiles, Kartendaten © OpenStreetMap-Mitwirkende.

Pendelfuchs ist Open Source (GPL-3.0) und kostenlos.
```

**Weitere Felder**

| Feld | Wert |
|---|---|
| Support-URL | `https://pendelfuchs.de/hilfe.html` |
| Marketing-URL (optional) | `https://pendelfuchs.de/` |
| Copyright | `2026 Rico Kullmann` |
| Kategorie | Primär **Navigation**, sekundär **Reisen** |
| Preis | Kostenlos |
| Verfügbarkeit | Deutschland (optional zusätzlich Österreich und Schweiz – die App ist nur auf Deutsch) |
| Geräte | nur iPhone (das iPad ist nicht eingerichtet) |

## App-Datenschutz

| Feld | Wert |
|---|---|
| Datenschutzrichtlinie-URL | `https://pendelfuchs.de/datenschutz.html` |
| Erfasst die App Daten? | **Nein – „Keine Daten erfasst“** |
| Tracking | Nein |

Begründung: Apple versteht unter „erfassen“, dass Daten das Gerät so verlassen, dass du oder in die App
eingebauter Fremdcode (Analyse, Werbung, SDKs) sie länger nutzen können, als für die Antwort auf die Anfrage
nötig. Pendelfuchs hat keinen eigenen Server, kein Analyse- oder Werbe-SDK; die Anfragen an Transitous, VVO,
TLMS und OpenFreeMap dienen nur dazu, die Anfrage sofort zu beantworten. Der Standort geht nur für
„In der Nähe“ an den Fahrplandienst. Diese Einordnung ist meine Lesart von Apples Definition, keine
Rechtsberatung. Wer auf Nummer sicher gehen will, gibt **Standort → Ungefährer Standort → App-Funktionalität,
nicht mit der Identität verknüpft, kein Tracking** an – das wäre ebenfalls korrekt.

Das Datenschutz-Manifest (`PrivacyInfo.xcprivacy` in App und Widgets) passt dazu: kein Tracking, keine
erfassten Daten, UserDefaults nur innerhalb von App und App Group.

## Altersfreigabe

Alle Fragen mit **Nein / Keine** beantworten: keine Gewalt, keine Glücksspiele, keine Inhalte für Erwachsene,
kein uneingeschränkter Webzugriff (der DB-Link öffnet Safari bzw. den DB Navigator außerhalb der App), keine
Nutzerinhalte, kein Chat. Ergebnis: **4+**.

## Rechtliches und Händlerstatus

| Feld | Wert |
|---|---|
| Händlerstatus (EU, Digital Services Act) | **Kein Händler** – die App ist kostenlos und ohne Werbung, Käufe oder Spenden. Bei Unsicherheit rechtlich beraten lassen. |
| Exportvorschriften / Verschlüsselung | Keine eigene Verschlüsselung; `ITSAppUsesNonExemptEncryption = NO` ist bereits gesetzt, App Store Connect fragt deshalb nicht nach. |
| Inhaltsrechte | „Enthält Inhalte Dritter?“ → **Ja**: Fahrplandaten von Transitous (CC BY 4.0) und VVO, Fahrzeugpositionen von TLMS, Karten von OpenFreeMap/OpenStreetMap (ODbL). Die Rechte bzw. Erlaubnisse sind in `docs/DATENQUELLEN.md` und `docs/ANFRAGEN.md` festgehalten – TLMS hat zugestimmt (27.11.2026); vor dem Einreichen sollte die Antwort des VVO da sein. |

## Hinweise für die App-Prüfung (App Review Information)

| Feld | Wert |
|---|---|
| Anmeldung erforderlich | Nein |
| Kontakt | Rico Kullmann, Telefon und E-Mail-Adresse eintragen (sieht nur Apple) |

**Notizen für die Prüfer (Englisch)**
```
Pendelfuchs is a free, ad-free public transport app for Germany. No account or login is needed.

To try the main features:
1. "Verbindungen" tab: search e.g. from "Dresden Hbf" to "Pirna Bahnhof", open a connection and tap the star to save it, then pick weekdays.
2. In the saved trip, tap "Live-Aktivität starten" to see the Live Activity on the Lock Screen and in the Dynamic Island.
3. Location is optional and only used for "In der Nähe" (nearby stops).

Data sources: Transitous (transitous.org, open data for all of Germany), the regional transit authority VVO in the Dresden area, live vehicle positions from TLMS (tlm.solutions) for Dresden trams and city buses, map tiles from OpenFreeMap. The app has no backend server; all requests go directly from the device to these services.
```

## TestFlight (externe Tester)

Unter **TestFlight → Testinformationen**. Die Beta-Prüfung bei Apple betrifft den ersten Build jeder Version.

| Feld | Wert |
|---|---|
| Feedback-E-Mail | `kontakt@pendelfuchs.de` |
| Marketing-URL | `https://pendelfuchs.de/` |
| Datenschutzrichtlinie-URL | `https://pendelfuchs.de/datenschutz.html` |
| Anmeldung erforderlich | Nein |
| Kontakt für die Beta-Prüfung | wie bei der App-Prüfung (sieht nur Apple) |
| Notizen für die Prüfer | die englischen Notizen aus „Hinweise für die App-Prüfung“ |

**Beta-App-Beschreibung** (sehen die Tester)
```
Pendelfuchs ist eine kostenlose Fahrplan-App für ganz Deutschland – ohne Werbung, ohne Konto, ohne eigenen Server.

• Abfahrten an Haltestellen, mit Echtzeit, Gleis und Störungen
• Verbindungssuche mit Umstiegen, Karte und Fahrtverlauf
• „Meine Fahrten“: regelmäßige Wege wie den Arbeitsweg speichern
• Erinnerung vor der Abfahrt und Meldungen bei Verspätung, Ausfall oder knappem Anschluss
• Live-Aktivität auf dem Sperrbildschirm und in der Dynamic Island
• Widgets und Siri-Kurzbefehle
• In Dresden: Straßenbahnen und Stadtbusse live auf der Karte

Daten: Transitous (offene Fahrplandaten für ganz Deutschland), zusätzlich die Auskünfte einiger Verkehrsverbünde. Der Quellcode ist offen: github.com/binaryscream/pendelfuchs
```

**Was zu testen ist** (für Build 0.1.0 – bei jedem Build anpassen)
```
Danke fürs Testen! Am meisten hilft der Alltag: Leg deinen Arbeits- oder Schulweg unter „Meine Fahrten“ an (Verbindung suchen → Stern → Wochentage wählen) und nutz die App ein paar Tage.

Bitte achte besonders auf:
• Stimmen Abfahrten, Verspätungen und Gleise mit dem, was du am Bahnsteig siehst?
• Kommt die Erinnerung vor der Abfahrt pünktlich? Lässt sich daraus die Live-Aktivität starten (Meldung gedrückt halten)?
• Aktualisiert sich die Live-Aktivität unterwegs, und verschwindet sie nach der Ankunft?
• Kommen Meldungen bei Verspätung oder Ausfall – und wie spät nach dem eigentlichen Ereignis?
• Zeigen die Widgets die richtigen nächsten Abfahrten?

Bekannt: Im Hintergrund prüft die App nur, wenn iOS sie weckt (oft etwa alle 15 Minuten). Meldungen können deshalb etwas später kommen.

Feedback: in der App einen Screenshot machen und „Feedback senden“ wählen – oder per E-Mail an kontakt@pendelfuchs.de.
```

## Bildschirmfotos

Pflicht ist ein Satz für das **6,9-Zoll-iPhone** (Hochformat **1320 × 2868** Pixel, PNG oder JPEG, ohne
Transparenz, 1 bis 10 Bilder). App Store Connect verkleinert ihn selbst für kleinere iPhones. Aufnehmen im
Simulator „iPhone 18 Pro Max“ – der hat genau diese Größe.

Fertige Bilder in `design/app-store/` (1320 × 2868, PNG ohne Transparenz): mit Überschrift und Geräterahmen
gestaltet, aus 1206 × 2622 auf die 6,9-Zoll-Größe hochgerechnet. Die unbearbeiteten Simulator-Aufnahmen liegen in
`design/app-store/roh/`. In dieser Reihenfolge hochladen:

| Datei | Überschrift | Inhalt |
|---|---|---|
| `01-meine-fahrten.png` | Dein Arbeitsweg. Einfacher. | Zwei regelmäßige Fahrten, „pünktlich“ |
| `02-live-aktivitaet.png` | Deine Fahrt in Echtzeit | Live-Aktivität auf dem Sperrbildschirm |
| `03-abfahrten.png` | Alle Abfahrten im Blick | Dresden Hauptbahnhof mit Echtzeit, Auslastung, Ausfall |
| `04-verbindungssuche.png` | Finde deine nächste Verbindung | Pirna → Dresden Postplatz mit Preisen |
| `05-verbindung.png` | Entspannt ans Ziel | Zeitleiste, Preis, Tarifzonen |
| `06-karte.png` | Behalte deine Route im Blick | Karte mit Streckenverlauf |
| `07-widgets.png` | Alles auf deinem Homescreen | Widgets und Countdown in der Dynamic Island |
| `08-erinnerung.png` | Verpasse keine Abfahrt | Erinnerung mit Knopf „Live-Aktivität starten“ |

Schönheitsfehler: Auf Bild 2 steht oben links „Carrier“ (Simulator). Bei Bedarf übermalen.

## Vor dem ersten Hochladen

- [x] Bezahltes Entwicklerkonto (27.11.2026, Team-ID unverändert, dringliche Meldungen eingeschaltet)
- [x] Domain, Website online, E-Mail-Adresse in App und Impressum eingetragen (`kontakt@pendelfuchs.de`)
- [x] Kontakt-URL im User-Agent für Transitous auf die Website umgestellt (`TransitousProvider.contactURL`)
- [ ] Antworten von VVO, TLMS und Transitous umgesetzt (`docs/ANFRAGEN.md`) – Transitous und TLMS erledigt, VVO offen
- [ ] Erlaubnis der regionalen Verbünde (TripKit) geklärt (Anfragen: `docs/ANFRAGEN.md`, Abschnitt 4) – oder die TripKit-Verbünde vor dem Hochladen im Code abschalten (`useRegional` im Router)
- [ ] Quelltext auf GitHub öffentlich (Bedingung von Transitous)
- [ ] Rechtstexte geprüft
- [x] Bildschirmfotos aufgenommen (`design/app-store/`)
- [ ] Version `1.0` statt `0.1.0` (`MARKETING_VERSION` in `project.yml`)

# App-Store-Eintrag – zum Kopieren in App Store Connect

Stand 27.11.2026. Alles auf Deutsch, Sprache des Eintrags: **Deutsch**. Die Zeichengrenzen sind geprüft
(Zahlen in Klammern). Adressen mit `pendelfuchs.de` setzen voraus, dass die Website dort liegt – sonst anpassen.

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
Fahrplandaten für ganz Deutschland von Transitous (u. a. DELFI e. V., CC BY 4.0), im Gebiet des Verkehrsverbunds Oberelbe zusätzlich vom VVO. Live-Fahrzeuge in Dresden von TLMS. Karten von OpenFreeMap, © OpenMapTiles, Kartendaten © OpenStreetMap-Mitwirkende.

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
| Inhaltsrechte | „Enthält Inhalte Dritter?“ → **Ja**: Fahrplandaten von Transitous (CC BY 4.0) und VVO, Fahrzeugpositionen von TLMS, Karten von OpenFreeMap/OpenStreetMap (ODbL). Die Rechte bzw. Erlaubnisse sind in `docs/DATENQUELLEN.md` und `docs/ANFRAGEN.md` festgehalten – vor dem Einreichen sollten die Antworten von VVO und TLMS da sein. |

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

## Bildschirmfotos

Pflicht ist ein Satz für das **6,9-Zoll-iPhone** (Hochformat **1320 × 2868** Pixel, PNG oder JPEG, ohne
Transparenz, 1 bis 10 Bilder). App Store Connect verkleinert ihn selbst für kleinere iPhones. Aufnehmen im
Simulator „iPhone 18 Pro Max“ – der hat genau diese Größe.

Vorschlag, in dieser Reihenfolge:
1. **Meine Fahrten** mit zwei regelmäßigen Fahrten und Live-Status („pünktlich“)
2. **Live-Aktivität** auf dem Sperrbildschirm
3. **Abfahrten** an einer Dresdner Haltestelle mit Echtzeit
4. **Verbindung** mit Zeitleiste und Live-Fahrzeug
5. **Karte** mit Streckenverlauf
6. **Widgets** auf dem Home-Bildschirm
7. **Erinnerung** vor der Abfahrt mit Knopf „Live-Aktivität starten“

## Vor dem ersten Hochladen

- [ ] Bezahltes Entwicklerkonto
- [ ] Domain, Website online, E-Mail-Adresse in App und Impressum eingetragen
- [ ] Kontakt-URL im User-Agent für Transitous auf die Website umgestellt (`TransitousProvider.contactURL`)
- [ ] Antworten von VVO, TLMS und Transitous umgesetzt (`docs/ANFRAGEN.md`)
- [ ] Quelltext auf GitHub öffentlich (Bedingung von Transitous)
- [ ] Rechtstexte geprüft
- [ ] Bildschirmfotos aufgenommen
- [ ] Version `1.0` statt `0.1.0` (`MARKETING_VERSION` in `project.yml`)

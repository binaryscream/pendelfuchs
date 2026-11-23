# Regionen: TripKit-Anbieter und wo man anfragt – Stand 23.11.2026

Grundlage: die Anbieterliste von **TripKit** (github.com/alexander-albers/tripkit, MIT) – welche Schnittstelle
dort genutzt wird – und die **offiziellen Webseiten** der Verbünde: gibt es ein offizielles Angebot, und wo
fragt man nach Zugang/Erlaubnis?

Kontakte stehen nur hier, wenn sie auf einer offiziellen Seite genannt sind. „–“ heißt: nichts gefunden.
Vor dem Anschreiben die Seite noch einmal öffnen – Adressen ändern sich.

**Grundabdeckung** für ganz Deutschland liefert schon Transitous. Eine Region lohnt sich zusätzlich, wenn der
Verbund **Echtzeit, Preise oder eine Verbindungs-API** offiziell anbietet.

## A – Offizielle API mit klarem Zugangsweg (zuerst anfragen)

| Region | TripKit nutzt | Offizielles Angebot | Wo anfragen |
|---|---|---|---|
| **VRR** Rhein-Ruhr | EFA `vrr.de/vrr-efa/` | OpenVRR: EFA-JSON und TRIAS (Testserver frei, Produktiv nach Zusage), Infrastruktur-API CC BY 4.0; Nutzungsvereinbarung kostenfrei | **openvrr@vrr.de** (Produktivzugang), opendata-oepnv@vrr.de (Nutzung über Test/Hobby hinaus, mit Projektbeschreibung) – opendata-oepnv.de → VRR → OpenVRR |
| **VRS** Rhein-Sieg (Köln/Bonn) | eigene App-API `ekap-app.vrs.de` | OpenService: ASS, **TRIAS** oder **GTFS-RT**; GTFS-Soll unter DL-DE Zero 2.0 | **api@vrs.de** – Projektbeschreibung (max. 500 Zeichen) + unterschriebene Nutzungsvereinbarung (PDF auf vrs.de/fuer-unternehmen/open-data-service) |
| **HVV** Hamburg | Geofox GTI | Geofox-GTI-API kostenfrei: Verbindungen mit Tarif, Abfahrten, **Echtzeit**; nur für Endkunden-Auskunft, widerrufbar | **api@hochbahn.de**, Betreff „Bitte um Geofox-API-Zugang“, Ansprechpartner + kurze Beschreibung (hvv.de → Datenabruf) |
| **VBN** Bremen/Niedersachsen | HAFAS `fahrplaner.vbn.de` | GTFS, **GTFS-RT** (CC BY-SA 4.0), OTP-Routing-API mit Key; HAFAS/TRIAS nur begrenzt | **api@vbn.de** (OTP-API-Key, kurze Beschreibung) – vbn.de/service/entwicklerinfos |
| **Connect** (Niedersachsen/Bremen) | – | TRIAS-API (EFA), GTFS Norddeutschland | Antragsformular auf connect-fahrplanauskunft.de (id=opendata) |
| **RMV** Rhein-Main | HAFAS `rmv.de/auskunft/gate` | RMV-API (HAFAS) mit Zugangsschlüssel, Haltestellendaten | Online-Formular „API-Zugang anfordern“ auf rmv.de/s/de/rmv-open-data |
| **KVV** Karlsruhe | EFA `projekte.kvv-efa.de` | GTFS (CC0) + **TRIAS**; ausdrücklich für nicht-kommerzielle Apps | **fahrplan@kvv.karlsruhe.de** – Nutzungsvereinbarung (PDF auf kvv.de → Open Data) ausgefüllt einsenden |
| **VRN** Rhein-Neckar | EFA `vrn.de/mngvrn/` | **TRIAS** ohne Anmeldung (2.500 Anfragen/h), **GTFS-RT** Bus/Tram, DL-DE BY 2.0 | Kontaktformular opendata.vrn.de/contact; im TRIAS-Datensatz genannt: m.mueller@vrn.de |
| **VVO** Oberelbe (schon eingebaut) | EFA `efa.vvo-online.de` | WebAPI (inoffiziell), TRIAS laut Community-Doku nach Absprache | **opendata@vvo-online.de** (Angabe aus der Community-Doku, nicht von der VVO-Seite) |

## B – Offene Fahrplandaten, aber keine Echtzeit-API gefunden

Diese Daten stecken meist schon in Transitous (über DELFI). Anfragen lohnt sich nur, wenn sie eine API anbieten.

| Region | TripKit nutzt | Offizielles Angebot | Kontakt |
|---|---|---|---|
| **MVV** München | EFA `efa.mvv-muenchen.de` | GTFS + CSV (CC BY); TRIAS „demnächst“, EFA in geschlossener Beta | – (Entwicklerseite: mvv-muenchen.de → MVV-Content für Entwickler) |
| **Bayern** (BEG/DEFAS) | EFA mobile `defas-fgi.de/beg` | DEFAS-Soll in NeTEx/GTFS, **TRIAS**-Verbindungsauskunft, VDV 453 | info@bahnland-bayern.de / Kontaktformular beg.bahnland-bayern.de; Datenplattform bayerninfo.de/datenangebot |
| **VGN** Nürnberg | EFA `vgn.defas-fgi.de` | GTFS (CC BY 3.0 DE), vierteljährlich | info@vgn.de / vgn.de/kontakt |
| **AVV** Augsburg | EFA `fahrtauskunft.avv-augsburg.de` | GTFS Regionalbus (CC BY 4.0) | kundencenter@avv-augsburg.de |
| **NVBW** Baden-Württemberg | EFA `efa-bw.de/nvbw` | GTFS BW (DL-DE BY 2.0), MobiData BW | opendata@nvbw.de, mobidata-bw@nvbw.de |
| **VMT** Mittelthüringen | HAFAS `vmt.hafas.de` | GTFS Verbund + Thüringen (CC BY, Lizenzlink widersprüchlich) | service@vmt-thueringen.de |
| **VMS** Mittelsachsen | EFA `efa.vms.de` | GTFS (CC BY 4.0), wöchentlich | info@vms.de |
| **VVV** Vogtland | EFA `vogtlandauskunft.de` | GTFS + VDV452 (Lizenz nicht angegeben) | mail@vvvogtland.de |
| **VVS** Stuttgart | EFA `www3.vvs.de` | Open Data über opendata-oepnv.de (nicht geprüft) | – (Kontaktformular vvs.de/service/kontakt) |

## C – Kein offizielles Angebot gefunden

Nur allgemeine Kontakte; hier zuerst fragen, ob es überhaupt einen Datenzugang gibt.

| Region | TripKit nutzt | Allgemeiner Kontakt |
|---|---|---|
| VBB Berlin-Brandenburg | HAFAS `fahrinfo.vbb.de` | – (vbb.de/kontakt) |
| BVG Berlin | HAFAS `bvg-apps.hafas.de` | – (Kontaktformular bvg.de) |
| NAH.SH Schleswig-Holstein | HAFAS `nahsh.hafas.cloud` | – |
| GVH Hannover (üstra) | HAFAS `gvh.hafas.de` | – (Kontaktformular uestra.de) |
| VSN Süd-Niedersachsen | HAFAS `fahrplaner.vsninfo.de` | info@vsninfo.de |
| VOS Osnabrück | HAFAS `fahrplan.vos.info` | kundenservice@vos.info |
| VMV Mecklenburg-Vorpommern | EFA `fahrplanauskunft-mv.de` | – |
| KVB Köln | HAFAS `auskunft.kvb.koeln` | – (Köln ist über VRS abgedeckt) |
| NRW (mobil.nrw) | EFA `ticketshop.mobil.nrw` | – |
| Westfalen (Westfalenfahrplan, moBiel, MVG) | EFA `westfalenfahrplan.de` | info@westfalentarif.de |
| AVV Aachen | (Datei in TripKit nicht gefunden) | – (avv.de nicht lesbar) |
| NVV Nordhessen | HAFAS `auskunft.nvv.de` | – (Kontakt-Dialog nvv.de) |
| saarVV Saarland | HAFAS `saarfahrplan.de` | service@saarvv.de |
| DING Ulm | EFA `ding.eu/ding3` | – (Kontaktformular ding.eu) |
| naldo | EFA `naldo.de` | – |
| VAG Freiburg / RVF | EFA `efa.vagfr.de` | – |
| NASA / INSA Sachsen-Anhalt | HAFAS `reiseauskunft.insa.de` | info@nasa.de (geschäftlich) |
| BSVG Braunschweig | EFA `fahrplanauskunft.bsvg.net` | – (Regionalverband: info@rv-bs.de) |
| INVG Ingolstadt | HAFAS `fpa.invg.de` | – (Webseite nicht erreichbar) |
| VVM Mainfranken | EFA mobile `defas-fgi.de/vvmapp` | – (Webseite nicht erreichbar) |

## Deutsche Bahn

TripKit nutzt die DB-Navigator-Schnittstelle `app.services-bahn.de/mob/` (inoffiziell). Offiziell gibt es keine
frei nutzbare Verbindungssuche; siehe `DATENQUELLEN.md`. Züge kommen über Transitous.

## Außerhalb Deutschlands (in TripKit, nicht recherchiert)

Österreich: ÖBB, Wien (Wiener Linien), VOR, OÖVV, Linz, Salzburg (SVV), Tirol (VVT), Innsbruck (IVB),
Vorarlberg (VMOBIL), Steiermark (STV). Schweiz: SBB, search.ch, ZVV, BLS, BVB Basel, TPG Genf.
Italien: Südtirol (STA). Europa: RailTeam.

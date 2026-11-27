# Entwurf: Anfrage an den VVO

**An:** opendata@vvo-online.de
**Betreff:** Anfrage zur Nutzung der VVO-Schnittstellen in einer Open-Source-Fahrplan-App (Pendelfuchs)

---

Guten Tag,

ich entwickle die freie, nicht-kommerzielle iOS-App „Pendelfuchs“ (Lizenz GPL-3.0, Quelltext auf GitHub, derzeit
noch privat, die Veröffentlichung ist geplant). Die App zeigt Abfahrten, Verbindungen und Echtzeitdaten und bietet
Widgets sowie Live-Aktivitäten für regelmäßige Fahrten. Sie wird kostenlos, ohne Werbung und ohne Tracking angeboten.

Im Verbundgebiet des VVO nutze ich bislang die WebAPI (`webapi.vvo-online.de`: `/dm`, `/dm/trip`, `/tr/trips`,
`/tr/pointfinder`), außerhalb die Daten von Transitous. Mir ist bewusst, dass die WebAPI nicht offiziell
dokumentiert ist. Ich möchte sie deshalb mit Ihrer Zustimmung und rücksichtsvoll verwenden.

Dazu meine Fragen:

1. Darf die App die WebAPI im oben beschriebenen Umfang für eine nicht-kommerzielle Open-Source-App nutzen?
   Falls es Bedingungen gibt (Quellenangabe, Obergrenze für Anfragen, Kennzeichnung der App), halte ich sie gern ein.
2. Gibt es für diesen Zweck eine offizielle Schnittstelle, die Sie empfehlen, etwa TRIAS oder den SIRI-ET-Feed?
   Ich würde die App darauf umstellen, wenn das für Sie besser ist.
3. Wie viele Anfragen sind unbedenklich? Die App fragt Daten nur bei Bedarf ab (Widgets etwa alle 15 Minuten,
   Fahrtverläufe nur für angezeigte Verbindungen) und speichert nichts auf eigenen Servern.
4. Darf ich in der App die Quelle „Daten: VVO“ ausweisen?

Vielen Dank für Ihre Zeit und eine kurze Rückmeldung.

Freundliche Grüße
[Name]
[Kontakt / Link zum Projekt]

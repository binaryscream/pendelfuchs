// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct ServiceAlertTests {
    @Test func decodesVVORouteChanges() throws {
        let alerts = try VVODecoding.decode(RouteChangesResponse.self, from: fixture("vvo-rc")).alerts
        #expect(alerts.count == 4)
        let bannewitz = try #require(alerts["28192"])
        #expect(bannewitz.title == "Sperrung Windbergstraße in Bannewitz")
        #expect(bannewitz.text?.hasPrefix("Aufgrund einer Vollsperrung") == true, "Überschrift nicht doppelt, kein HTML")
        #expect(bannewitz.text?.contains("<") == false)
        #expect(bannewitz.validFrom != nil && bannewitz.validUntil != nil)
    }

    @Test func departuresCarryRouteChanges() throws {
        let departures = try VVODecoding.decode(DepartureMonitorResponse.self, from: fixture("dm-dresden-hbf")).departures
        let withChanges = try #require(departures.first { !$0.alerts.isEmpty })
        let known = Dictionary(uniqueKeysWithValues: withChanges.alerts.map {
            (String($0.id.dropFirst(4)), ServiceAlert(id: $0.id, title: "Bauarbeiten"))
        })
        let resolved = withChanges.alerts.resolvingVVO(known, at: .now)
        #expect(resolved.count == withChanges.alerts.count && resolved.allSatisfy { $0.title == "Bauarbeiten" })
        #expect(withChanges.alerts.resolvingVVO([:], at: .now).isEmpty, "unbekannte Meldungen fallen weg")
    }

    @Test func expiredAlertsAreDropped() {
        let old = ServiceAlert(id: "vvo:1", title: "Alt", validFrom: .distantPast, validUntil: Date(timeIntervalSince1970: 0))
        #expect([ServiceAlert.vvoPlaceholder("1")].resolvingVVO(["1": old], at: .now).isEmpty)
    }

    @Test func onlyValidWithinItsPeriods() {
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let alert = ServiceAlert(id: "x", title: "Bauarbeiten", validFrom: start, validUntil: start + 30 * day,
                                 periods: [DateInterval(start: start, duration: day),
                                           DateInterval(start: start + 29 * day, duration: day)])
        #expect(alert.isValid(at: start + 3600))
        #expect(!alert.isValid(at: start + 10 * day), "zwischen den Zeiträumen gilt die Meldung nicht")
        #expect(alert.isValid(at: start + 29.5 * day))
    }

    @Test func stripsHTML() {
        let text = ServiceAlert.plainText(fromHTML: "<h2><b>Titel</b></h2><div>Zeile&nbsp;1</div><div><br></div><ul><li>A</li></ul>")
        #expect(text == "Titel\nZeile 1\n\n• A")
    }

    @Test func transitousTrackChangeAndAlerts() throws {
        let json = """
        {"stopTimes":[{"place":{"name":"Dresden Hbf","stopId":"x","scheduledDeparture":"2026-11-25T06:00:00Z",
          "departure":"2026-11-25T06:02:00Z","track":"3","scheduledTrack":"1",
          "alerts":[{"headerText":"Bauarbeiten Dresden–Pirna","descriptionText":"Ersatzverkehr mit Bussen",
                     "impactPeriod":[{"start":"2026-11-20T00:00:00Z","end":"2026-12-01T00:00:00Z"}]}]},
          "mode":"SUBURBAN","realTime":true,"headsign":"Pirna","displayName":"S1","tripId":"t1"}]}
        """
        let response = try TransitousAPI.decode(TransitousAPI.StopTimesResponse.self, from: Data(json.utf8))
        let departure = try #require(response.stopTimes.first?.departure)
        #expect(departure.platform == "3" && departure.scheduledPlatform == "1" && departure.platformChanged)
        #expect(departure.alerts.first?.title == "Bauarbeiten Dresden–Pirna")
        #expect(departure.alerts.first?.text == "Ersatzverkehr mit Bussen")
    }
}

/// Echte Abfrage – nur mit `FAHRPLAN_LIVE_TESTS=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FAHRPLAN_LIVE_TESTS"] == "1"))
struct ServiceAlertLiveTests {
    @Test func dresdenHbfHasResolvedAlerts() async throws {
        await LiveThrottle.shared.wait()
        let departures = try await VVOProvider().departures(
            at: Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof", place: "Dresden"), limit: 40)
        let alerts = departures.flatMap(\.alerts)
        #expect(!alerts.isEmpty)
        #expect(alerts.allSatisfy { !$0.title.isEmpty })
    }
}

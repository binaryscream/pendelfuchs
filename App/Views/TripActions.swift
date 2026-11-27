// SPDX-License-Identifier: GPL-3.0-or-later

import EventKit
import EventKitUI
import FahrplanKit
import SwiftUI

/// „In Kalender eintragen“ und „Bei der DB buchen“ für eine Verbindung.
struct TripActionsSection: View {
    let trip: Trip

    @Environment(\.stopNameStyle) private var style
    @State private var showCalendar = false

    var body: some View {
        Section {
            Button {
                showCalendar = true
            } label: {
                Label("In Kalender eintragen", systemImage: "calendar.badge.plus")
            }
            // Am Knopf selbst – an einer Listen-Section angehängt erscheint das Blatt nicht.
            .sheet(isPresented: $showCalendar) {
                CalendarEventSheet(trip: trip, style: style)
                    .ignoresSafeArea()
            }
            if let url = BahnBooking.url(for: trip) {
                Link(destination: url) {
                    Label("Ticket bei der DB suchen", systemImage: "ticket")
                }
            }
        } footer: {
            Text("Öffnet die Verbindungssuche von bahn.de bzw. den DB Navigator mit Start, Ziel und Uhrzeit. Die App selbst verkauft keine Tickets.")
        }
    }
}

/// Link zur Verbindungssuche auf bahn.de (öffnet auf dem iPhone den DB Navigator, falls installiert).
enum BahnBooking {
    static func url(for trip: Trip) -> URL? {
        guard let first = trip.rides.first?.stops.first, let last = trip.rides.last?.stops.last else { return nil }
        let origin = StopNameStyle.label(name: first.name, place: first.place, style: .withPlace)
        let destination = StopNameStyle.label(name: last.name, place: last.place, style: .withPlace)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let time = formatter.string(from: trip.departure.scheduledTime)

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=@+#")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value }

        // Ohne Bahnhofsnummer sucht bahn.de über den Namen (`A=1@O=<Name>@`).
        let parameters = [
            ("sts", "true"),
            ("so", origin), ("zo", destination),
            ("soid", "A=1@O=\(origin)@"), ("zoid", "A=1@O=\(destination)@"),
            ("hd", time), ("hza", "D"), ("kl", "2"),
        ]
        let fragment = parameters.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: "https://www.bahn.de/buchung/fahrplan/suche#\(fragment)")
    }
}

/// Systemdialog zum Anlegen eines Kalendereintrags (ab iOS 17 ohne Kalenderzugriff der App).
struct CalendarEventSheet: UIViewControllerRepresentable {
    let trip: Trip
    let style: StopNameStyle

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let rides = trip.rides
        let origin = rides.first?.stops.first
        let destination = rides.last?.stops.last
        let from = origin.map { StopNameStyle.label(name: $0.name, place: $0.place, style: style) } ?? ""
        let to = destination.map { StopNameStyle.label(name: $0.name, place: $0.place, style: style) } ?? ""

        event.title = "\(from) → \(to)"
        // Wie in den Notizen: Fahrplanzeiten. Eine momentane Verspätung gehört nicht in den Kalender.
        event.startDate = trip.departure.scheduledTime
        event.endDate = max(trip.arrival.scheduledTime, trip.departure.scheduledTime)
        event.location = from
        event.notes = notes(for: rides)
        event.addAlarm(EKAlarm(relativeOffset: -10 * 60))

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    /// Eine Zeile je Fahrt: „7:42 S1 Pirna (Gl. 1) → 8:04 Dresden Hbf“.
    private func notes(for rides: [TripLeg]) -> String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        let lines = rides.compactMap { ride -> String? in
            guard let first = ride.stops.first, let last = ride.stops.last,
                  let dep = ride.departure, let arr = ride.arrival else { return nil }
            let platform = first.platform.map { " (\((ride.mode ?? .other).platformLabel($0)))" } ?? ""
            return "\(dep.scheduledTime.formatted(time)) \(ride.line ?? "") \(first.label(style))\(platform)"
                + " → \(arr.scheduledTime.formatted(time)) \(last.label(style))"
        }
        return (lines + ["", "Aus Pendelfuchs – Zeiten laut Fahrplan."]).joined(separator: "\n")
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true)
        }
    }
}

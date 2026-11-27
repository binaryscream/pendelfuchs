// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import FahrplanKit
import SwiftUI
import WidgetKit

// MARK: - Konfiguration

/// Strecken-Widget: die nächsten Verbindungen von A nach B. Ab einer wählbaren Uhrzeit zeigt es automatisch
/// den Rückweg (B → A); ein Knopf im Widget tauscht die Richtung von Hand.
struct SelectRouteIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Strecke"
    static let description = IntentDescription("Die nächsten Verbindungen von A nach B – mit Rückweg ab einer Uhrzeit.")

    @Parameter(title: "Von", description: "Startpunkt des Hinwegs.")
    var origin: StopEntity?

    @Parameter(title: "Nach", description: "Ziel des Hinwegs.")
    var destination: StopEntity?

    @Parameter(title: "Rückweg automatisch", default: true)
    var automaticReturn: Bool

    @Parameter(title: "Rückweg ab", default: DateComponents(hour: 14, minute: 0), kind: .time)
    var returnTime: DateComponents

    @Parameter(title: "Nur Deutschlandticket", default: false)
    var deutschlandTicketOnly: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$origin) → \(\.$destination)") {
            \.$automaticReturn
            \.$returnTime
            \.$deutschlandTicketOnly
        }
    }

    /// Wendezeit; `nil`, wenn der Rückweg nicht automatisch umgeschaltet werden soll.
    var turnTime: TimeOfDay? {
        guard automaticReturn else { return nil }
        return TimeOfDay(hour: returnTime.hour ?? 14, minute: returnTime.minute ?? 0)
    }
}

/// Knopf „Richtung tauschen“ im Widget. Gilt bis zum nächsten Tagesabschnitt (Wendezeit bzw. Mitternacht).
struct SwapRouteIntent: AppIntent {
    static let title: LocalizedStringResource = "Richtung tauschen"
    static let isDiscoverable = false

    @Parameter(title: "Schlüssel")
    var key: String

    /// Wendezeit in Minuten seit Mitternacht; -1 = keine automatische Umschaltung.
    @Parameter(title: "Wendezeit")
    var turnMinutes: Int

    init() {}

    init(key: String, turnMinutes: Int) {
        self.key = key
        self.turnMinutes = turnMinutes
    }

    func perform() async throws -> some IntentResult {
        let turn = turnMinutes >= 0 ? TimeOfDay(hour: turnMinutes / 60, minute: turnMinutes % 60) : nil
        let state = RouteDirection.toggled(at: .now, turnAt: turn, state: RouteWidgetStore.state(for: key))
        RouteWidgetStore.save(state, for: key)
        return .result()
    }
}

/// Merkt sich pro Strecke, ob der Nutzer die Richtung getauscht hat (App Group, damit Knopf und Widget es teilen).
enum RouteWidgetStore {
    static func key(_ origin: Stop, _ destination: Stop) -> String {
        "routeWidget.swap.\(origin.id)>\(destination.id)"
    }

    static func state(for key: String) -> RouteSwapState? {
        AppGroup.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(RouteSwapState.self, from: $0) }
    }

    static func save(_ state: RouteSwapState, for key: String) {
        if let data = try? JSONEncoder().encode(state) { AppGroup.defaults.set(data, forKey: key) }
    }
}

// MARK: - Zeitleiste

/// Eine Verbindung samt komplettem Lauf des Fahrzeugs (falls bekannt) für den Fortschrittsbalken.
struct RouteTrip {
    let trip: Trip
    let run: TripLeg?
}

struct RouteEntry: TimelineEntry {
    enum Content {
        case trips([RouteTrip])
        case message(String)
    }

    let date: Date
    /// Angezeigte Richtung (bereits getauscht, falls Rückweg).
    let from: Stop?
    let to: Stop?
    let reversed: Bool
    let turnTime: TimeOfDay?
    let swap: SwapRouteIntent?
    let content: Content

    /// Antippen öffnet die Verbindungssuche mit dieser Strecke.
    var linkURL: URL? {
        guard let from, let to else { return nil }
        return DeepLink.url(forRoute: from, to)
    }

    func linkURL(for trip: Trip) -> URL? {
        guard let from, let to else { return nil }
        return DeepLink.url(forRoute: from, to, trip: trip)
    }
}

struct RouteProvider: AppIntentTimelineProvider {
    private static let sampleFrom = Stop(provider: .vvo, stopID: "33003370", name: "Bahnhof", place: "Pirna")
    private static let sampleTo = Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof", place: "Dresden")

    func placeholder(in context: Context) -> RouteEntry {
        RouteEntry(date: .now, from: Self.sampleFrom, to: Self.sampleTo, reversed: false, turnTime: nil, swap: nil,
                   content: .trips(Self.sampleTrips().map { RouteTrip(trip: $0, run: nil) }))
    }

    func snapshot(for configuration: SelectRouteIntent, in context: Context) async -> RouteEntry {
        if context.isPreview { return placeholder(in: context) }
        return await load(configuration).first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectRouteIntent, in context: Context) async -> Timeline<RouteEntry> {
        let entries = await load(configuration)
        let failed = entries.contains { if case .message = $0.content { true } else { false } }
        // Spätestens zur nächsten Richtungsumschaltung neu laden, sonst alle 15 Minuten (Widget-Budget).
        let turn = configuration.turnTime
        let next = min(Date.now.addingTimeInterval(failed ? 5 * 60 : 15 * 60),
                       RouteDirection.nextChange(after: .now, turnAt: turn))
        return Timeline(entries: entries, policy: .after(max(next, .now.addingTimeInterval(60))))
    }

    private func load(_ configuration: SelectRouteIntent) async -> [RouteEntry] {
        guard let origin = configuration.origin?.stop, let destination = configuration.destination?.stop else {
            return [RouteEntry(date: .now, from: nil, to: nil, reversed: false, turnTime: configuration.turnTime, swap: nil,
                               content: .message("Widget bearbeiten und Start und Ziel wählen."))]
        }

        let turn = configuration.turnTime
        let key = RouteWidgetStore.key(origin, destination)
        let state = RouteWidgetStore.state(for: key)
        let swap = SwapRouteIntent(key: key, turnMinutes: turn.map { $0.hour * 60 + $0.minute } ?? -1)

        // Ein Eintrag pro Minute; die Richtung wird je Eintrag bestimmt (kann innerhalb der 15 Minuten wechseln).
        let now = Date.now
        let start = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
        // Für 45 Minuten vorausplanen: iOS lädt oft später neu als gewünscht.
        let dates = (0..<45).map { start.addingTimeInterval(Double($0) * 60) }
        let directions = dates.map { RouteDirection.isReversed(at: $0, turnAt: turn, state: state) }

        let options = TripOptions(deutschlandTicketOnly: configuration.deutschlandTicketOnly)
        var loaded: [Bool: Result<[RouteTrip], Error>] = [:]
        for reversed in Set(directions) {
            let query = TripQuery(origin: reversed ? destination : origin, destination: reversed ? origin : destination,
                                  time: now, options: options)
            do {
                let router = DataSources.router()
                let trips = try await router.trips(query)
                // Den kompletten Lauf nur für die angezeigten Verbindungen holen.
                var result: [RouteTrip] = []
                for trip in trips {
                    let upcoming = trip.departure.expectedTime >= now.addingTimeInterval(-30)
                    result.append(RouteTrip(trip: trip, run: upcoming && result.count < 5 ? await router.fullRun(of: trip) : nil))
                }
                loaded[reversed] = .success(result)
            } catch { loaded[reversed] = .failure(error) }
        }

        return zip(dates, directions).compactMap { date, reversed -> RouteEntry? in
            let from = reversed ? destination : origin
            let to = reversed ? origin : destination
            switch loaded[reversed] {
            case .success(let trips):
                // Bereits abgefahrene Verbindungen fallen mit der Zeit heraus.
                let upcoming = trips.filter {
                    $0.trip.departure.expectedTime >= date.addingTimeInterval(-30)
                        && (!CancelledDisplay.hide || !$0.trip.isCancelledForRider)
                }
                // Geht nur die geladene Liste zu Ende, nicht „Keine Verbindungen“ behaupten – lieber hier aufhören.
                if date != start, upcoming.isEmpty, !trips.isEmpty { return nil }
                return RouteEntry(date: date == start ? now : date, from: from, to: to, reversed: reversed, turnTime: turn,
                                  swap: swap, content: upcoming.isEmpty ? .message("Keine Verbindungen gefunden.") : .trips(upcoming))
            default:
                return RouteEntry(date: date == start ? now : date, from: from, to: to, reversed: reversed, turnTime: turn,
                                  swap: swap, content: .message("Keine Verbindung zum Fahrplandienst."))
            }
        }
    }

    private static func sampleTrips() -> [Trip] {
        let now = Date.now
        func ride(_ line: String, _ mode: TransportMode, from start: Double, minutes: Double) -> TripLeg {
            TripLeg(kind: .ride, mode: mode, line: line, stops: [
                TripStop(stopID: "a", name: "A", place: nil, platform: nil, arrival: nil,
                         departure: TimePoint(scheduledTime: now.addingTimeInterval(start * 60))),
                TripStop(stopID: "b", name: "B", place: nil, platform: nil,
                         arrival: TimePoint(scheduledTime: now.addingTimeInterval((start + minutes) * 60)), departure: nil),
            ])
        }
        return [
            Trip(legs: [ride("S1", .suburbanRailway, from: 6, minutes: 22), ride("7", .tram, from: 30, minutes: 8)], interchanges: 1),
            Trip(legs: [ride("S2", .suburbanRailway, from: 21, minutes: 24), ride("3", .tram, from: 48, minutes: 8)], interchanges: 1),
            Trip(legs: [ride("S1", .suburbanRailway, from: 36, minutes: 22)], interchanges: 0),
            Trip(legs: [ride("S1", .suburbanRailway, from: 66, minutes: 22)], interchanges: 0),
        ]
    }
}

// MARK: - Widget

struct RouteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "de.fahrplanxl.route", intent: SelectRouteIntent.self,
                               provider: RouteProvider()) { entry in
            RouteWidgetView(entry: entry)
        }
        .configurationDisplayName("Strecke")
        .description("Die nächsten Verbindungen von A nach B. Ab einer Uhrzeit automatisch der Rückweg, mit Tausch-Knopf.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Darstellung

struct RouteWidgetView: View {
    @AppStorage(StopNameStyle.storageKey, store: AppGroup.defaults) private var style = StopNameStyle.withPlace
    let entry: RouteEntry
    @Environment(\.widgetFamily) private var family

    private var maxRows: Int {
        switch family {
        case .systemLarge: 5
        case .accessoryRectangular: 2
        default: 2
        }
    }

    var body: some View {
        content
            .padding(.horizontal, family == .accessoryRectangular ? 0 : 6)
            .padding(.vertical, family == .accessoryRectangular ? 0 : 10)
            .containerBackground(for: .widget) { Color(.systemBackground) }
            .widgetURL(entry.linkURL)
    }

    @ViewBuilder private var content: some View {
        if family == .accessoryRectangular {
            lockScreen
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header
                switch entry.content {
                case .message(let text):
                    Spacer(minLength: 0)
                    Text(text).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                case .trips(let trips):
                    let shown = Array(trips.prefix(maxRows).enumerated())
                    ForEach(shown, id: \.offset) { index, item in
                        if index > 0 { Divider() }
                        // Antippen öffnet genau diese Verbindung in der App.
                        Link(destination: entry.linkURL(for: item.trip) ?? entry.linkURL ?? URL(string: "fahrplanxl://")!) {
                            RouteTripRow(trip: item.trip, run: item.run, now: entry.date)
                                // Eine Verbindung = ein Satz, statt Zeiten, Balken und Linien einzeln.
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Self.spoken(item.trip))
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(label(entry.from, other: entry.to)).lineLimit(1)
                    Image(systemName: "arrow.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(label(entry.to, other: entry.from)).lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .minimumScaleFactor(0.8)

                if let turn = entry.turnTime, family == .systemLarge {
                    Text(entry.reversed ? "Rückweg · ab \(turn.formatted) automatisch" : "Hinweg · Rückweg ab \(turn.formatted)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if let swap = entry.swap {
                Button(intent: swap) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.footnote.weight(.bold))
                        .frame(width: 26, height: 26)
                        .background(Color(.secondarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Richtung tauschen")
            }
        }
    }

    /// Haltestellenname in der gewählten Darstellung; bei „Nur Name“ und gleichen Namen
    /// („Bahnhof“ → „Bahnhof“) trotzdem mit Ort, sonst wären Start und Ziel nicht zu unterscheiden.
    private func label(_ stop: Stop?, other: Stop?) -> String {
        guard let stop else { return "…" }
        if style == .nameOnly, stop.name == other?.name { return stop.label(.withPlace) }
        return stop.label(style)
    }

    /// Für VoiceOver: „Abfahrt 7:42, 3 Minuten Verspätung, Ankunft 8:20, mit S1, dann 7, Gleis 2, ein Umstieg“.
    static func spoken(_ trip: Trip) -> String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        var parts = ["Abfahrt \(trip.departure.expectedTime.formatted(time))"]
        if let disruption = trip.disruption {
            parts.append(disruption.rerouteNote)
        } else if let delay = trip.departure.delayMinutes, delay > 0 {
            parts.append("\(delay) \(delay == 1 ? "Minute" : "Minuten") Verspätung")
        }
        parts.append("Ankunft \(trip.arrival.expectedTime.formatted(time))")
        let lines = trip.rides.compactMap(\.line)
        if !lines.isEmpty { parts.append("mit \(lines.joined(separator: ", dann "))") }
        if let first = trip.rides.first, let stop = first.stops.first, let platform = stop.platform, !platform.isEmpty {
            let label = (first.mode ?? .other).platformLabel(platform).replacingOccurrences(of: "Gl. ", with: "Gleis ")
            parts.append(stop.platformChanged ? "\(label), geändert" : label)
        }
        if trip.interchanges > 0 { parts.append(trip.interchanges == 1 ? "ein Umstieg" : "\(trip.interchanges) Umstiege") }
        return parts.joined(separator: ", ")
    }

    /// Sperrbildschirm: einfarbig, Strecke und die nächsten zwei Verbindungen.
    @ViewBuilder private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(label(entry.from, other: entry.to)) → \(label(entry.to, other: entry.from))")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if case .trips(let trips) = entry.content {
                ForEach(Array(trips.prefix(maxRows).enumerated()), id: \.offset) { _, item in
                    let trip = item.trip
                    HStack(spacing: 4) {
                        Text("\(trip.departure.expectedTime.formatted(date: .omitted, time: .shortened)) → \(trip.arrival.expectedTime.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                        Spacer(minLength: 2)
                        Text(trip.rides.compactMap(\.line).prefix(3).joined(separator: "›")).lineLimit(1)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.spoken(trip))
                }
            } else {
                Text("Keine Verbindungen").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RouteTripRow: View {
    let trip: Trip
    let run: TripLeg?
    let now: Date

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                DelayedTimeText(scheduled: trip.departure.scheduledTime, actual: trip.departure.realTime, inline: true)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Spacer(minLength: 4)
                if trip.disruption != nil {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                        .accessibilityLabel("Verbindung gestört")
                }
                DelayedTimeText(scheduled: trip.arrival.scheduledTime, actual: trip.arrival.realTime, inline: true)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
            }

            RouteBar(trip: trip, run: run, now: now)

            // Links Gleis, in der Mitte die Linien, rechts die Dauer.
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    if let first = trip.rides.first?.stops.first, let platform = first.platform, !platform.isEmpty {
                        if first.platformChanged {
                            Text("Gl. \(platform) statt \(first.scheduledPlatform ?? "")")
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Gl. \(platform)")
                        }
                    }
                    if !AlertDisplay.current.filter(trip).isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            .accessibilityLabel("Hinweis zur Fahrt")
                    }
                    if trip.interchanges > 0 {
                        Text("\(trip.interchanges)×").foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 3) {
                    ForEach(Array(trip.rides.prefix(3).enumerated()), id: \.offset) { _, ride in
                        LineBadge(line: ride.line ?? "?", mode: ride.mode ?? .other, compact: true)
                            .frame(minWidth: 44)
                            .scaleEffect(0.85)
                            .frame(height: 19)
                    }
                }
                .fixedSize()

                Text(duration).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var duration: String {
        let minutes = Int((trip.duration / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60):\(String(format: "%02d", minutes % 60)) h"
    }
}

/// Fortschrittsbalken über den kompletten Lauf des Fahrzeugs (Endhalt bis Endhalt). Der eigene Abschnitt
/// (Einstieg bis Ausstieg) ist kräftiger getönt, der schon gefahrene Teil voll in der Linienfarbe.
/// Ohne bekannten Lauf zeigt er stattdessen die Verbindung selbst.
private struct RouteBar: View {
    let trip: Trip
    let run: TripLeg?
    let now: Date

    private var color: Color { (trip.rides.first?.mode ?? .other).color }

    /// (Start, Ende) des gesamten Laufs und des eigenen Abschnitts.
    private var span: (start: Date, end: Date, mineFrom: Date, mineTo: Date) {
        let mineFrom = trip.departure.expectedTime, mineTo = trip.arrival.expectedTime
        if let run, let a = run.departure?.expectedTime, let b = run.arrival?.expectedTime, b > a {
            return (min(a, mineFrom), max(b, mineTo), mineFrom, mineTo)
        }
        return (mineFrom, mineTo, mineFrom, mineTo)
    }

    private func x(_ date: Date, _ width: CGFloat) -> CGFloat {
        let span = span
        let total = max(1, span.end.timeIntervalSince(span.start))
        return width * CGFloat(min(1, max(0, date.timeIntervalSince(span.start) / total)))
    }

    var body: some View {
        let span = span
        let done = trip.disruption == nil
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.16))
                Capsule().fill(color.opacity(0.4))
                    .frame(width: max(4, x(span.mineTo, w) - x(span.mineFrom, w)))
                    .offset(x: x(span.mineFrom, w))
                if done {
                    Capsule().fill(color).frame(width: x(now, w))
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)   // reine Zierde – die Zeiten stehen darüber
    }
}

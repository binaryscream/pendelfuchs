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

struct RouteEntry: TimelineEntry {
    enum Content {
        case trips([Trip])
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
}

struct RouteProvider: AppIntentTimelineProvider {
    private static let sampleFrom = Stop(provider: .vvo, stopID: "33003370", name: "Bahnhof", place: "Pirna")
    private static let sampleTo = Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof", place: "Dresden")

    func placeholder(in context: Context) -> RouteEntry {
        RouteEntry(date: .now, from: Self.sampleFrom, to: Self.sampleTo, reversed: false, turnTime: nil, swap: nil,
                   content: .trips(Self.sampleTrips()))
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
        let dates = (0..<15).map { start.addingTimeInterval(Double($0) * 60) }
        let directions = dates.map { RouteDirection.isReversed(at: $0, turnAt: turn, state: state) }

        let options = TripOptions(deutschlandTicketOnly: configuration.deutschlandTicketOnly)
        var loaded: [Bool: Result<[Trip], Error>] = [:]
        for reversed in Set(directions) {
            let query = TripQuery(origin: reversed ? destination : origin, destination: reversed ? origin : destination,
                                  time: now, options: options)
            do { loaded[reversed] = .success(try await DataSources.router().trips(query)) }
            catch { loaded[reversed] = .failure(error) }
        }

        return zip(dates, directions).map { date, reversed in
            let from = reversed ? destination : origin
            let to = reversed ? origin : destination
            switch loaded[reversed] {
            case .success(let trips):
                // Bereits abgefahrene Verbindungen fallen mit der Zeit heraus.
                let upcoming = trips.filter { $0.departure.expectedTime >= date.addingTimeInterval(-30) }
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
            .containerBackground(for: .widget) { Color(.systemBackground) }
            .widgetURL(entry.linkURL)
    }

    @ViewBuilder private var content: some View {
        if family == .accessoryRectangular {
            lockScreen
        } else {
            VStack(alignment: .leading, spacing: 4) {
                header
                switch entry.content {
                case .message(let text):
                    Spacer(minLength: 0)
                    Text(text).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                case .trips(let trips):
                    let shown = Array(trips.prefix(maxRows).enumerated())
                    ForEach(shown, id: \.offset) { index, trip in
                        Divider()
                        RouteTripRow(trip: trip, now: entry.date)
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
                        .frame(width: 30, height: 30)
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

    /// Sperrbildschirm: einfarbig, Strecke und die nächsten zwei Verbindungen.
    @ViewBuilder private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(label(entry.from, other: entry.to)) → \(label(entry.to, other: entry.from))")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if case .trips(let trips) = entry.content {
                ForEach(Array(trips.prefix(maxRows).enumerated()), id: \.offset) { _, trip in
                    HStack(spacing: 4) {
                        Text("\(trip.departure.expectedTime.formatted(date: .omitted, time: .shortened)) → \(trip.arrival.expectedTime.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                        Spacer(minLength: 2)
                        Text(trip.rides.compactMap(\.line).prefix(3).joined(separator: "›")).lineLimit(1)
                    }
                    .font(.caption)
                }
            } else {
                Text("Keine Verbindungen").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RouteTripRow: View {
    let trip: Trip
    let now: Date

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                DelayedTimeText(scheduled: trip.departure.scheduledTime, actual: trip.departure.realTime)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Spacer(minLength: 4)
                if trip.disruption != nil {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                }
                DelayedTimeText(scheduled: trip.arrival.scheduledTime, actual: trip.arrival.realTime)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
            }

            RouteBar(trip: trip, now: now)

            HStack(spacing: 5) {
                if let platform = trip.rides.first?.stops.first?.platform, !platform.isEmpty {
                    Text("Gl. \(platform)")
                }
                if trip.interchanges > 0 {
                    Text("\(trip.interchanges)×").foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                let rides = trip.rides
                ForEach(Array(rides.prefix(3).enumerated()), id: \.offset) { _, ride in
                    LineBadge(line: ride.line ?? "?", mode: ride.mode ?? .other, compact: true)
                        .scaleEffect(0.85, anchor: .trailing)
                        .frame(height: 19)
                }
                Text(duration).monospacedDigit()
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

/// Reiseverlauf als Balken: jede Fahrt in der Farbe ihres Verkehrsmittels, Umstiege als blasse Lücke,
/// Längen im Verhältnis zur Fahrzeit.
private struct RouteBar: View {
    let trip: Trip
    let now: Date

    /// Anteil der Gesamtstrecke (0…1), der zur Zeit `now` schon zurückgelegt ist.
    private var progress: Double { trip.overallProgress(at: now) ?? 0 }

    private struct Segment { let weight: Double; let color: Color? }

    private var segments: [Segment] {
        var result: [Segment] = []
        var cursor = trip.departure.expectedTime
        for ride in trip.rides {
            guard let start = ride.departure?.expectedTime, let end = ride.arrival?.expectedTime, end > start else { continue }
            if start > cursor { result.append(Segment(weight: start.timeIntervalSince(cursor), color: nil)) }
            result.append(Segment(weight: end.timeIntervalSince(start), color: (ride.mode ?? .other).color))
            cursor = end
        }
        return result.isEmpty ? [Segment(weight: 1, color: .gray)] : result
    }

    var body: some View {
        let parts = segments
        let total = parts.reduce(0) { $0 + $1.weight }
        GeometryReader { proxy in
            let gaps = CGFloat(parts.count - 1) * 2
            let bar = HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Capsule()
                        .fill(part.color ?? Color.secondary.opacity(0.5))
                        .frame(width: max(4, (proxy.size.width - gaps) * part.weight / total))
                }
            }
            bar.opacity(0.22)
            bar.mask(alignment: .leading) {
                Rectangle().frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 5)
    }
}

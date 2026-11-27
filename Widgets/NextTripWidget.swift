// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import FahrplanKit
import SwiftUI
import WidgetKit

// MARK: - Konfiguration (welche Fahrt?)

struct SelectSavedTripIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Fahrt wählen"
    static let description = IntentDescription("Zeigt die nächste Fahrt einer gemerkten Verbindung.")

    @Parameter(title: "Fahrt", description: "Leer lassen für die nächste regelmäßige Fahrt.")
    var trip: SavedTripEntity?
}

// MARK: - Zeitleiste

struct NextTripEntry: TimelineEntry {
    enum Content {
        /// Aktueller Stand laut Echtzeit; `note` gesetzt, wenn es die Ersatzverbindung ist.
        case live(Trip, note: String?)
        /// Keine Daten erreichbar oder Verbindung nicht gefunden: nur die gemerkten Fahrplanzeiten.
        case planned(reason: String)
        case message(String)
    }

    let date: Date
    let saved: SavedTrip?
    /// Abfahrt des gezeigten Termins laut Fahrplan.
    let occurrence: Date?
    let content: Content
}

struct NextTripProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextTripEntry { Self.sample() }

    func snapshot(for configuration: SelectSavedTripIntent, in context: Context) async -> NextTripEntry {
        if context.isPreview { return Self.sample() }
        return await load(configuration)
    }

    func timeline(for configuration: SelectSavedTripIntent, in context: Context) async -> Timeline<NextTripEntry> {
        let entry = await load(configuration)
        return Timeline(entries: [entry], policy: .after(Self.nextReload(for: entry)))
    }

    /// Kurz vor und während der Fahrt oft neu laden, sonst selten – das Widget-Budget von iOS ist knapp.
    static func nextReload(for entry: NextTripEntry, now: Date = .now) -> Date {
        guard let occurrence = entry.occurrence else { return now.addingTimeInterval(60 * 60) }
        let untilDeparture = occurrence.timeIntervalSince(now)
        if untilDeparture > 90 * 60 {
            // Spätestens eine Stunde vor der Abfahrt wieder nachsehen, sonst alle zwei Stunden.
            return min(occurrence.addingTimeInterval(-60 * 60), now.addingTimeInterval(2 * 3600))
        }
        if case .planned = entry.content { return now.addingTimeInterval(5 * 60) }
        return now.addingTimeInterval(untilDeparture > 30 * 60 ? 15 * 60 : 5 * 60)
    }

    private func load(_ configuration: SelectSavedTripIntent) async -> NextTripEntry {
        let now = Date.now
        let chosen: SavedTrip? = await MainActor.run {
            let store = SavedTripsStore(defaults: AppGroup.defaults)
            if let id = configuration.trip?.id { return store.trip(id: id) }
            return store.regular(now: now).first
        }
        guard let saved = chosen else {
            let text = configuration.trip == nil
                ? "Merke in der App eine Fahrt und lege Wochentage fest."
                : "Diese Fahrt ist nicht mehr gespeichert. Widget bearbeiten und eine andere wählen."
            return NextTripEntry(date: now, saved: nil, occurrence: nil, content: .message(text))
        }

        let occurrence = Self.occurrence(of: saved, now: now)
        do {
            let trips = try await DataSources.router().trips(saved.query(on: occurrence))
            guard let resolved = saved.resolve(in: trips, now: now) else {
                return NextTripEntry(date: now, saved: saved, occurrence: occurrence,
                                     content: .planned(reason: "Nicht gefunden"))
            }
            return NextTripEntry(date: now, saved: saved, occurrence: occurrence,
                                 content: .live(resolved.trip, note: resolved.note))
        } catch {
            return NextTripEntry(date: now, saved: saved, occurrence: occurrence,
                                 content: .planned(reason: "Keine Echtzeit"))
        }
    }

    /// Der Termin, der jetzt zählt: bei regelmäßigen Fahrten der nächste (eine laufende Fahrt bleibt bis zur
    /// Ankunft stehen), sonst heute bzw. morgen.
    static func occurrence(of saved: SavedTrip, now: Date) -> Date {
        let duration = saved.arrival.map { arrival -> TimeInterval in
            let minutes = (arrival.minutesSinceMidnight - saved.departure.minutesSinceMidnight + 24 * 60) % (24 * 60)
            return TimeInterval(minutes * 60)
        } ?? 30 * 60
        let grace = max(15 * 60, duration + 5 * 60)
        if let next = saved.nextOccurrence(after: now, grace: grace) { return next }
        let today = saved.departure.date(on: now) ?? now
        return today > now.addingTimeInterval(-grace) ? today : today.addingTimeInterval(24 * 3600)
    }

    private static func sample() -> NextTripEntry {
        let now = Date.now
        let start = now.addingTimeInterval(14 * 60)
        func stop(_ id: String, _ name: String, _ place: String, _ platform: String, arr: Date?, dep: Date?) -> TripStop {
            TripStop(stopID: id, name: name, place: place, platform: platform,
                     arrival: arr.map { TimePoint(scheduledTime: $0, realTime: $0.addingTimeInterval(120)) },
                     departure: dep.map { TimePoint(scheduledTime: $0, realTime: $0.addingTimeInterval(120)) })
        }
        let leg = TripLeg(kind: .ride, mode: .suburbanRailway, line: "S1", stops: [
            stop("a", "Bahnhof", "Pirna", "2", arr: nil, dep: start),
            stop("b", "Hauptbahnhof", "Dresden", "13", arr: start.addingTimeInterval(22 * 60), dep: nil),
        ])
        let trip = Trip(legs: [leg], interchanges: 0)
        let origin = Stop(provider: .vvo, stopID: "33003370", name: "Bahnhof", place: "Pirna")
        let destination = Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof", place: "Dresden")
        var saved = SavedTrip(trip: trip, query: TripQuery(origin: origin, destination: destination),
                              weekdays: Weekday.workdays)
        saved.name = "Zur Arbeit"
        return NextTripEntry(date: now, saved: saved, occurrence: start, content: .live(trip, note: nil))
    }
}

// MARK: - Widget

struct NextTripWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "de.pendelfuchs.nexttrip", intent: SelectSavedTripIntent.self,
                               provider: NextTripProvider()) { entry in
            NextTripWidgetView(entry: entry)
        }
        .configurationDisplayName("Meine nächste Fahrt")
        .description("Abfahrt, Gleis und Verspätung deiner nächsten gemerkten Fahrt – mit Knopf für die Live-Aktivität.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Darstellung

struct NextTripWidgetView: View {
    @AppStorage(StopNameStyle.storageKey, store: AppGroup.defaults) private var style = StopNameStyle.withPlace
    let entry: NextTripEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) { Color(.systemBackground) }
            .widgetURL(entry.saved.flatMap { DeepLink.url(forSavedTrip: $0.id) })
    }

    @ViewBuilder private var content: some View {
        if let saved = entry.saved, let occurrence = entry.occurrence {
            let info = Info(saved: saved, occurrence: occurrence, content: entry.content, now: entry.date)
            switch family {
            case .accessoryRectangular: lockScreen(saved, info)
            case .systemMedium: medium(saved, info)
            default: small(saved, info)
            }
        } else if case .message(let text) = entry.content {
            VStack(alignment: .leading, spacing: 6) {
                Label("Meine nächste Fahrt", systemImage: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(text).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Klein

    private func small(_ saved: SavedTrip, _ info: Info) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // VoiceOver liest die Fahrt als einen Satz (am Titel); die Einzelteile darunter bleiben stumm.
            Text(saved.title(style: style))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .accessibilityLabel(info.spoken(title: saved.title(style: style)))
            Group {
                departure(info, size: .title)
                whenLine(info)
                lines(info, limit: 2)
            }
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 4) {
                status(info).accessibilityHidden(true)
                Spacer(minLength: 0)
                liveButton(saved, info, compact: true)
            }
        }
    }

    // MARK: Mittel

    private func medium(_ saved: SavedTrip, _ info: Info) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(saved.title(style: style))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityLabel(info.spoken(title: saved.title(style: style))
                        + ", Ankunft \(info.arrival.formatted(date: .omitted, time: .shortened))")
                Group {
                    departure(info, size: .largeTitle)
                    whenLine(info)
                    Spacer(minLength: 0)
                    status(info)
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Group {
                    lines(info, limit: 3)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text("an \(info.arrival.formatted(date: .omitted, time: .shortened))").monospacedDigit()
                    }
                    .font(.subheadline)
                    if let platform = info.platformText {
                        Text(platform)
                            .font(.caption.weight(info.platformChanged ? .semibold : .regular))
                            .foregroundStyle(info.platformChanged ? Color.orange : Color.secondary)
                    }
                }
                .accessibilityHidden(true)
                Spacer(minLength: 0)
                liveButton(saved, info, compact: false)
            }
        }
    }

    // MARK: Sperrbildschirm

    private func lockScreen(_ saved: SavedTrip, _ info: Info) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(saved.title(style: style)).font(.caption.weight(.semibold)).lineLimit(1)
            HStack(spacing: 4) {
                Text(info.departure.formatted(date: .omitted, time: .shortened)).fontWeight(.bold).monospacedDigit()
                if info.delay > 0 { Text("+\(info.delay)") }
                Text(saved.lines.prefix(3).joined(separator: "›")).lineLimit(1)
                if let platform = info.platformText { Text(platform).lineLimit(1) }
            }
            .font(.caption)
            Text(info.statusText).font(.caption2).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.spoken(title: saved.title(style: style)))
    }

    // MARK: Bausteine

    /// Abfahrtszeit groß; bei Verspätung die tatsächliche Zeit in Farbe, bei Ausfall durchgestrichen.
    private func departure(_ info: Info, size: Font.TextStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(info.departure.formatted(date: .omitted, time: .shortened))
                .font(.system(size, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(info.cancelled ? Color.red : info.delay >= 3 ? Color.red : info.delay > 0 ? Color.orange : Color.primary)
                .strikethrough(info.cancelled, color: .red)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if info.delay > 0, !info.cancelled {
                Text("+\(info.delay)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(info.delay >= 3 ? .red : .orange)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.spokenDeparture)
    }

    /// „in 12 Min.“ (läuft von selbst weiter) kurz vor der Abfahrt, sonst der Tag.
    @ViewBuilder private func whenLine(_ info: Info) -> some View {
        Group {
            if info.showsCountdown {
                Text(.currentDate, format: .reference(to: info.departure, allowedFields: [.hour, .minute], maxFieldCount: 2))
            } else {
                Text(info.dayText)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func lines(_ info: Info, limit: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(info.lines.prefix(limit).enumerated()), id: \.offset) { _, line in
                LineBadge(line: line.name, mode: line.mode, compact: true)
            }
            if family == .systemSmall, let platform = info.platformText {
                Text(platform)
                    .font(.caption2.weight(info.platformChanged ? .semibold : .regular))
                    .foregroundStyle(info.platformChanged ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func status(_ info: Info) -> some View {
        Text(info.statusText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(info.statusColor)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    /// Startet die Live-Aktivität dieser Fahrt – nur, wenn sie bald fährt oder gerade unterwegs ist.
    @ViewBuilder private func liveButton(_ saved: SavedTrip, _ info: Info, compact: Bool) -> some View {
        if info.canStartLive {
            Button(intent: StartSavedTripActivityIntent(id: saved.id)) {
                Label("Live", systemImage: "livephoto")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, compact ? 8 : 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .fixedSize()   // der Knopf behält seine Breite, der Status daneben kürzt notfalls
            .accessibilityLabel("Live-Aktivität starten")
        }
    }
}

// MARK: - Aufbereitete Angaben

/// Alles, was die Ansicht zeigt – aus Echtzeit, sonst aus den gemerkten Fahrplanzeiten.
private struct Info {
    let departure: Date
    let arrival: Date
    let delay: Int
    let cancelled: Bool
    let lines: [(name: String, mode: TransportMode)]
    let platformText: String?
    let platformChanged: Bool
    let statusText: String
    let statusColor: Color
    let dayText: String
    let showsCountdown: Bool
    let canStartLive: Bool

    init(saved: SavedTrip, occurrence: Date, content: NextTripEntry.Content, now: Date) {
        let calendar = Calendar.current
        var isUsable = true
        switch content {
        case .live(let trip, let note):
            departure = trip.departure.expectedTime
            arrival = trip.arrival.expectedTime
            delay = max(0, trip.departure.delayMinutes ?? 0)
            cancelled = trip.disruption != nil
            isUsable = trip.disruption == nil
            lines = trip.rides.map { ($0.line ?? "?", $0.mode ?? .other) }
            let first = trip.rides.first
            if let stop = first?.stops.first, let platform = stop.platform, !platform.isEmpty {
                platformText = (first?.mode ?? .other).platformLabel(platform)
                platformChanged = stop.platformChanged
            } else {
                platformText = nil
                platformChanged = false
            }
            if let disruption = trip.disruption {
                statusText = disruption.rerouteNote
                statusColor = .red
            } else if let note {
                statusText = "Ersatz: \(note)"
                statusColor = .orange
            } else if platformChanged {
                statusText = "Gleiswechsel"
                statusColor = .orange
            } else if delay > 0 {
                // Die Minuten stehen schon neben der Abfahrtszeit.
                statusText = "verspätet"
                statusColor = delay >= 3 ? .red : .orange
            } else if trip.departure.realTime != nil {
                statusText = "pünktlich"
                statusColor = .green
            } else {
                statusText = "laut Fahrplan"
                statusColor = .secondary
            }
        case .planned(let reason):
            departure = occurrence
            let minutes = saved.arrival.map {
                ($0.minutesSinceMidnight - saved.departure.minutesSinceMidnight + 24 * 60) % (24 * 60)
            } ?? 0
            arrival = occurrence.addingTimeInterval(TimeInterval(minutes * 60))
            delay = 0
            cancelled = false
            lines = zip(saved.lines, saved.modes).map { ($0, $1) }
            platformText = nil
            platformChanged = false
            statusText = reason
            statusColor = .secondary
        case .message:
            departure = occurrence
            arrival = occurrence
            delay = 0
            cancelled = false
            lines = []
            platformText = nil
            platformChanged = false
            statusText = ""
            statusColor = .secondary
        }

        if calendar.isDate(departure, inSameDayAs: now) {
            dayText = "heute"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(departure, inSameDayAs: tomorrow) {
            dayText = "morgen"
        } else {
            dayText = Weekday(date: departure, calendar: calendar).fullName
        }
        let untilDeparture = departure.timeIntervalSince(now)
        showsCountdown = !cancelled && untilDeparture > 0 && untilDeparture < 3 * 3600
        // Wie der Kurzbefehl: ab drei Stunden vor der Abfahrt bis zur Ankunft.
        canStartLive = isUsable && untilDeparture < 3 * 3600 && arrival > now
    }

    var spokenDeparture: String {
        let time = departure.formatted(date: .omitted, time: .shortened)
        if cancelled { return "Abfahrt \(time), fällt aus" }
        return delay > 0 ? "Abfahrt \(time), \(delay) \(delay == 1 ? "Minute" : "Minuten") Verspätung" : "Abfahrt \(time)"
    }

    func spoken(title: String) -> String {
        let lineText = lines.isEmpty ? "" : ", mit \(lines.map(\.name).joined(separator: ", dann "))"
        return "\(title), \(dayText), \(spokenDeparture)\(lineText)" + (platformText.map { ", \($0)" } ?? "")
            + ", \(statusText)"
    }
}

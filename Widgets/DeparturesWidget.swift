// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import FahrplanKit
import SwiftUI
import WidgetKit

// MARK: - Konfiguration (welche Haltestelle?)

/// Haltestelle als Auswahl im Widget-Bearbeiten-Dialog.
struct StopEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Haltestelle"
    static let defaultQuery = StopEntityQuery()

    /// Enthält die komplette Haltestelle, damit auch gesuchte (nicht favorisierte) Haltestellen funktionieren.
    let id: String
    let stop: Stop

    init?(_ stop: Stop) {
        guard let token = StopToken.encode(stop) else { return nil }
        id = token
        self.stop = stop
    }

    /// Behält die angefragte ID exakt bei (App Intents ordnet Ergebnisse über die ID zu).
    init?(id: String) {
        guard let stop = StopToken.decode(id) else { return nil }
        self.id = id
        self.stop = stop
    }

    var displayRepresentation: DisplayRepresentation {
        let style = StopNameStyle.current
        return DisplayRepresentation(title: "\(stop.label(style))", subtitle: "\(stop.secondaryLine(style) ?? "")")
    }
}

struct StopEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StopEntity] {
        identifiers.compactMap { StopEntity(id: $0) }
    }

    /// Ohne Suchtext: die Favoriten.
    @MainActor
    func suggestedEntities() async throws -> [StopEntity] {
        FavoritesStore(defaults: AppGroup.defaults).stops.compactMap(StopEntity.init)
    }

    /// Mit Suchtext: Treffer der Datenquelle, nach Nähe zu den Favoriten sortiert. Treffer weit weg von allen
    /// Favoriten (ganz Europa) fallen weg, solange es nähere gibt.
    func entities(matching string: String) async throws -> [StopEntity] {
        let found = try await DataSources.router().searchStops(query: string)
        let anchors = await MainActor.run {
            FavoritesStore(defaults: AppGroup.defaults).stops.compactMap(\.coordinate)
        }
        return StopSearchRegion.narrow(found, around: anchors).prefix(20).compactMap(StopEntity.init)
    }
}

struct SelectStopIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Haltestelle wählen"
    static let description = IntentDescription("Zeigt die nächsten Abfahrten dieser Haltestelle.")

    @Parameter(title: "Haltestelle", description: "Leer lassen für den ersten Favoriten.")
    var stop: StopEntity?
}

// MARK: - Zeitleiste

struct DeparturesEntry: TimelineEntry {
    enum Content {
        case departures([Departure])
        case message(String)
    }

    let date: Date
    let stop: Stop?
    let content: Content
}

struct DeparturesProvider: AppIntentTimelineProvider {
    private static let sampleStop = Stop(provider: .vvo, stopID: "33000028", name: "Hauptbahnhof", place: "Dresden")

    func placeholder(in context: Context) -> DeparturesEntry {
        DeparturesEntry(date: .now, stop: Self.sampleStop, content: .departures(Self.sampleDepartures()))
    }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> DeparturesEntry {
        if context.isPreview { return placeholder(in: context) }
        return await load(configuration).first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectStopIntent, in context: Context) async -> Timeline<DeparturesEntry> {
        let entries = await load(configuration)
        // Alle 15 Minuten neu laden (Widget-Budget von iOS), dazwischen zählt der Countdown minütlich herunter.
        let failed = entries.contains { if case .message = $0.content { true } else { false } }
        let next = Date.now.addingTimeInterval(failed ? 5 * 60 : 15 * 60)
        return Timeline(entries: entries, policy: .after(next))
    }

    private func load(_ configuration: SelectStopIntent) async -> [DeparturesEntry] {
        let fallback = await MainActor.run { FavoritesStore(defaults: AppGroup.defaults).stops.first }
        guard let stop = configuration.stop?.stop ?? fallback else {
            return [DeparturesEntry(date: .now, stop: nil,
                                    content: .message("Lege in der App einen Favoriten an oder wähle eine Haltestelle."))]
        }

        do {
            let departures = try await DataSources.router().departures(at: stop, limit: 20)
            // Ein Eintrag pro Minute: bereits abgefahrene Verbindungen fallen heraus.
            let now = Date.now
            let start = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
            return (0..<15).map { minute in
                let date = start.addingTimeInterval(Double(minute) * 60)
                let upcoming = departures.filter { $0.expectedTime >= date.addingTimeInterval(-30) }
                return DeparturesEntry(date: minute == 0 ? now : date, stop: stop, content: .departures(upcoming))
            }
        } catch {
            return [DeparturesEntry(date: .now, stop: stop, content: .message("Keine Verbindung zum Fahrplandienst."))]
        }
    }

    private static func sampleDepartures() -> [Departure] {
        let now = Date.now
        let samples: [(String, String, TransportMode, Double)] = [
            ("7", "Weixdorf", .tram, 2), ("S1", "Meißen", .suburbanRailway, 4), ("62", "Löbtau", .cityBus, 6),
            ("10", "Messe Dresden", .tram, 9), ("RB71", "Sebnitz", .train, 12), ("3", "Coschütz", .tram, 15),
            ("8", "Hellerau", .tram, 18), ("66", "Lockwitz", .cityBus, 21), ("S2", "Flughafen", .suburbanRailway, 24),
        ]
        return samples.map { line, direction, mode, minutes in
            let time = now.addingTimeInterval(minutes * 60)
            return Departure(id: "\(line)-\(minutes)", line: line, direction: direction, platform: nil, mode: mode,
                             scheduledTime: time, realTime: time, state: .onTime, occupancy: .unknown)
        }
    }
}

// MARK: - Widget

struct DeparturesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "de.fahrplanxl.departures", intent: SelectStopIntent.self,
                               provider: DeparturesProvider()) { entry in
            DeparturesWidgetView(entry: entry)
        }
        .configurationDisplayName("Abfahrten")
        .description("Die nächsten Abfahrten an einer Haltestelle.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Darstellung

struct DeparturesWidgetView: View {
    @AppStorage(StopNameStyle.storageKey, store: AppGroup.defaults) private var style = StopNameStyle.withPlace
    let entry: DeparturesEntry
    @Environment(\.widgetFamily) private var family

    private var maxRows: Int {
        switch family {
        case .systemSmall: 4
        case .systemMedium: 4
        case .systemLarge: 9
        case .accessoryRectangular: 2
        default: 3
        }
    }

    var body: some View {
        content
            .containerBackground(for: .widget) { Color(.systemBackground) }
            .widgetURL(entry.stop.flatMap(DeepLink.url(for:)))
    }

    @ViewBuilder private var content: some View {
        if family == .accessoryRectangular {
            lockScreen
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
                header
                switch entry.content {
                case .message(let text):
                    Spacer(minLength: 0)
                    Text(text).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                case .departures(let departures):
                    if departures.isEmpty {
                        Spacer(minLength: 0)
                        Text("Keine Abfahrten").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    } else {
                        ForEach(departures.prefix(maxRows)) { departure in
                            WidgetDepartureRow(departure: departure, now: entry.date, compact: family == .systemSmall)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "tram.fill").foregroundStyle(.tint)
            Text(entry.stop?.label(style) ?? "Fahrplan XL").fontWeight(.semibold).lineLimit(1)
            if family != .systemSmall, let second = entry.stop?.secondaryLine(style) {
                Text(second).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(family == .systemSmall ? .caption : .subheadline)
    }

    /// Sperrbildschirm: einfarbig, Haltestelle + zwei Abfahrten.
    @ViewBuilder private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.stop?.label(style) ?? "Fahrplan XL").font(.caption.weight(.semibold)).lineLimit(1)
            if case .departures(let departures) = entry.content, !departures.isEmpty {
                ForEach(departures.prefix(maxRows)) { departure in
                    HStack(spacing: 4) {
                        Text(departure.line).fontWeight(.bold)
                        Text(departure.direction).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(minutesText(departure, now: entry.date)).monospacedDigit()
                    }
                    .font(.caption)
                }
            } else {
                Text("Keine Abfahrten").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WidgetDepartureRow: View {
    @AppStorage(DelayDisplay.storageKey, store: AppGroup.defaults) private var style = DelayDisplay.badge
    let departure: Departure
    let now: Date
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            LineBadge(line: departure.line, mode: departure.mode, compact: true)
                .frame(width: compact ? 30 : 46)
                .scaleEffect(compact ? 0.9 : 1)
            Text(departure.direction)
                .font(compact ? .caption : .subheadline)
                .lineLimit(1)
                .strikethrough(departure.state == .cancelled)
            Spacer(minLength: 2)
            if !compact, style != .actual, let delay = departure.delayMinutes, delay > 0 {
                Text("+\(delay)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(delay >= 3 ? .red : .orange)
            }
            Text(minutesText(departure, now: now))
                .font((compact ? Font.caption : .subheadline).weight(.semibold).monospacedDigit())
                .foregroundStyle(departure.hasRealTime ? Color.primary : Color.secondary)
        }
    }
}

/// „jetzt“, „5 min“ oder bei mehr als einer Stunde die Uhrzeit.
private func minutesText(_ departure: Departure, now: Date) -> String {
    if departure.state == .cancelled { return "fällt aus" }
    let minutes = departure.minutesUntilDeparture(from: now)
    if minutes == 0 { return "jetzt" }
    if minutes < 60 { return "\(minutes) min" }
    return departure.expectedTime.formatted(date: .omitted, time: .shortened)
}


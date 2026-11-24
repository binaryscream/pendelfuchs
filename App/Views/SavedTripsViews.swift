// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

// MARK: - Tab „Meine Fahrten“

enum MyTripsRoute: Hashable {
    case saved(UUID)
    case detail(Trip, TripQuery)
}

struct MyTripsView: View {
    @Environment(SavedTripsStore.self) private var store
    @State private var path: [MyTripsRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                list(now: context.date)
            }
            .navigationTitle("Meine Fahrten")
            .navigationDestination(for: MyTripsRoute.self) { route in
                switch route {
                case .saved(let id): SavedTripDetailView(id: id)
                case .detail(let trip, let query): TripDetailView(trip: trip, query: query)
                }
            }
        }
    }

    @ViewBuilder private func list(now: Date) -> some View {
        let regular = store.regular(now: now)
        let bookmarked = store.bookmarked
        List {
            if !regular.isEmpty {
                Section("Regelmäßig") {
                    ForEach(regular) { row($0, now: now) }
                }
            }
            if !bookmarked.isEmpty {
                Section {
                    ForEach(bookmarked) { row($0, now: now) }
                } header: {
                    Text("Gemerkt")
                } footer: {
                    Text("Tippe eine Fahrt an und wähle Wochentage, um sie zur regelmäßigen Fahrt zu machen.")
                }
            }
        }
        .overlay {
            if store.trips.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Fahrten", systemImage: "star")
                } description: {
                    Text("Suche unter „Verbindungen“ eine Fahrt, öffne sie und tippe auf den Stern.")
                }
            }
        }
    }

    private func row(_ saved: SavedTrip, now: Date) -> some View {
        NavigationLink(value: MyTripsRoute.saved(saved.id)) {
            SavedTripRow(saved: saved, now: now)
        }
        .swipeActions {
            Button("Löschen", systemImage: "trash", role: .destructive) { store.remove(id: saved.id) }
        }
    }
}

/// Zeile mit Uhrzeit, Strecke, Linien, Wochentagen und – für die nächsten Stunden – Live-Status.
struct SavedTripRow: View {
    @Environment(\.stopNameStyle) private var style
    let saved: SavedTrip
    let now: Date

    @Environment(\.transit) private var transit
    @State private var live: LiveState = .idle

    private var upcoming: Date? { saved.upcomingDate(after: now) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(saved.departure.formatted)
                .font(.title2.weight(.semibold).monospacedDigit())

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(saved.title(style: style)).font(.body.weight(.medium)).lineLimit(2)
                    Spacer(minLength: 0)
                    LiveBadge(state: live)
                }
                HStack(spacing: 4) {
                    ForEach(Array(zip(saved.lines, saved.modes).enumerated()), id: \.offset) { index, pair in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        LineBadge(line: pair.0, mode: pair.1, compact: true)
                    }
                }
                HStack(spacing: 6) {
                    if saved.isRegular {
                        Label(saved.weekdays.summary, systemImage: "repeat")
                    }
                    if let upcoming, saved.isRegular {
                        Text("·")
                        Text(relativeDay(upcoming, now: now))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        // Live-Status nur für Fahrten in den nächsten 12 Stunden abfragen.
        // Alle 5 Minuten neu abfragen (die Zeile wird minütlich neu gezeichnet).
        .task(id: "\(upcoming?.timeIntervalSince1970 ?? 0)|\(Int(now.timeIntervalSince1970 / 300))") {
            guard let upcoming, upcoming.timeIntervalSince(now) < 12 * 3600 else { live = .idle; return }
            live = await LiveState.load(saved, on: upcoming, using: transit)
        }
    }
}

// MARK: - Detailansicht einer gemerkten Fahrt

struct SavedTripDetailView: View {
    @Environment(\.stopNameStyle) private var style
    let id: UUID

    @Environment(SavedTripsStore.self) private var store
    @Environment(\.transit) private var transit
    @Environment(\.dismiss) private var dismiss
    @State private var live: LiveState = .idle
    @State private var showSettings = false

    var body: some View {
        if let saved = store.trip(id: id) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(saved.origin.label(style)) → \(saved.destination.label(style))")
                            .font(.headline)
                        if let via = saved.via {
                            Text("über \(via.label(style))").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("Ab \(saved.departure.formatted)\(saved.arrival.map { " · an \($0.formatted)" } ?? "") · \(saved.lines.joined(separator: " › "))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if saved.isRegular {
                            Label(saved.weekdays.summary, systemImage: "repeat")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let upcoming = saved.upcomingDate() {
                    Section("Nächste Fahrt · \(relativeDay(upcoming, now: .now))") {
                        switch live {
                        case .idle, .loading:
                            HStack(spacing: 10) { ProgressView(); Text("Wird geladen …").foregroundStyle(.secondary) }
                        case .found(let trip):
                            NavigationLink(value: MyTripsRoute.detail(trip, saved.query(on: upcoming))) {
                                TripRow(trip: trip, now: .now)
                            }
                        case .rerouted(let trip, let note):
                            Label(note, systemImage: "arrow.triangle.branch")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            NavigationLink(value: MyTripsRoute.detail(trip, saved.query(on: upcoming))) {
                                TripRow(trip: trip, now: .now)
                            }
                        case .notFound:
                            Text("Diese Verbindung wurde zur gewohnten Zeit nicht gefunden – vielleicht hat sich der Fahrplan geändert.")
                                .foregroundStyle(.secondary)
                        case .failed(let message):
                            Text(message).foregroundStyle(.secondary)
                        }
                    }
                    .task(id: upcoming) {
                        // Solange die Ansicht offen ist, jede Minute aktualisieren.
                        while !Task.isCancelled {
                            let loaded = await LiveState.load(saved, on: upcoming, using: transit)
                            if case .failed = loaded, case .found = live {} else { live = loaded }
                            try? await Task.sleep(for: .seconds(60))
                        }
                    }

                    Section {
                        LiveActivityButton(saved: saved, knownTrip: { switch live { case .found(let t), .rerouted(let t, _): t; default: nil } }())
                    } footer: {
                        LiveActivityAutomationHint(saved: saved)
                    }
                }

            }
            .navigationTitle(saved.title(style: style))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Einstellungen", systemImage: "slider.horizontal.3") { showSettings = true }
            }
            .sheet(isPresented: $showSettings) { SavedTripSheet(id: id, isNew: false) }
            .onChange(of: store.trip(id: id) == nil) { _, removed in if removed { dismiss() } }
        } else {
            ContentUnavailableView("Fahrt gelöscht", systemImage: "trash")
        }
    }
}

// MARK: - Bearbeiten (Name, Wochentage)

/// Blatt, das direkt nach dem Merken erscheint.
struct SavedTripSheet: View {
    @Environment(\.stopNameStyle) private var style
    let id: UUID
    /// `true` direkt nach dem Merken, `false` beim späteren Öffnen der Einstellungen.
    var isNew = true

    @Environment(SavedTripsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let saved = store.trip(id: id) {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(saved.departure.formatted) · \(saved.origin.label(style)) → \(saved.destination.label(style))")
                                Text(saved.lines.joined(separator: " › ")).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                        }
                    }
                    SavedTripSettingsSections(id: id)
                    Section {
                        Button("Nicht mehr merken", role: .destructive) {
                            store.remove(id: id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Fahrt gemerkt" : "Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Name und Wochentage einer gemerkten Fahrt; Änderungen werden sofort gespeichert.
struct SavedTripSettingsSections: View {
    let id: UUID
    @Environment(SavedTripsStore.self) private var store

    var body: some View {
        if let saved = store.trip(id: id) {
            Section {
                WeekdayPicker(selection: binding(saved, \.weekdays))
            } header: {
                Text("Regelmäßig fahren")
            } footer: {
                Text(saved.isRegular
                     ? "\(saved.weekdays.summary) um \(saved.departure.formatted)"
                     : "Wähle die Tage, an denen du diese Fahrt nimmst.")
            }

            Section("Name (optional)") {
                TextField("z. B. Zur Arbeit", text: Binding(
                    get: { saved.name ?? "" },
                    set: { var s = saved; s.name = $0.isEmpty ? nil : $0; store.update(s) }
                ))
            }
        }
    }

    private func binding<T>(_ saved: SavedTrip, _ keyPath: WritableKeyPath<SavedTrip, T>) -> Binding<T> {
        Binding(
            get: { store.trip(id: saved.id)?[keyPath: keyPath] ?? saved[keyPath: keyPath] },
            set: { value in
                guard var current = store.trip(id: saved.id) else { return }
                current[keyPath: keyPath] = value
                store.update(current)
            }
        )
    }
}

/// Sieben runde Knöpfe Mo–So plus Schnellauswahl.
struct WeekdayPicker: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(Weekday.allCases) { day in
                    let selected = selection.contains(day)
                    Button {
                        if selected { selection.remove(day) } else { selection.insert(day) }
                    } label: {
                        Text(day.shortName)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(day.fullName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            HStack {
                preset("Mo–Fr", Weekday.workdays)
                preset("Täglich", Weekday.everyDay)
                preset("Keine", [])
            }
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func preset(_ title: String, _ days: Set<Weekday>) -> some View {
        Button(title) { selection = days }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(selection == days ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Live-Status

enum LiveState: Equatable {
    case idle
    case loading
    case found(Trip)
    /// Gemerkte Fahrt nicht fahrbar – stattdessen diese Verbindung (mit Hinweis).
    case rerouted(Trip, String)
    case notFound
    case failed(String)

    /// Sucht die gemerkte Verbindung am angegebenen Tag und gleicht sie ab.
    static func load(_ saved: SavedTrip, on day: Date, using transit: any TransitProvider) async -> LiveState {
        do {
            let trips = try await transit.trips(saved.query(on: day))
            guard let resolved = saved.resolve(in: trips) else { return .notFound }
            if let note = resolved.note { return .rerouted(resolved.trip, note) }
            return .found(resolved.trip)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Kleines Statusschild rechts in der Zeile: pünktlich / +3 / fällt aus.
private struct LiveBadge: View {
    let state: LiveState

    var body: some View {
        switch state {
        case .found(let trip):
            if let disruption = trip.disruption {
                badge(disruption.badgeText, .red)
            } else if let delay = trip.departure.delayMinutes, delay > 0 {
                badge("+\(delay)", delay >= 3 ? .red : .orange)
            } else if trip.departure.realTime != nil {
                badge("pünktlich", .green)
            }
        case .rerouted:
            badge("Umgeplant", .orange)
        case .notFound:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                .accessibilityLabel("Verbindung nicht gefunden")
        default:
            EmptyView()
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Hilfen

extension SavedTrip {
    /// Nächster sinnvoller Termin: bei regelmäßigen Fahrten der nächste gewählte Wochentag,
    /// bei nur gemerkten Fahrten heute (falls noch nicht vorbei) oder morgen.
    func upcomingDate(after now: Date = .now) -> Date? {
        if isRegular { return nextOccurrence(after: now) }
        let calendar = Calendar.current
        let today = departure.date(on: now, calendar: calendar)
        if let today, today >= now.addingTimeInterval(-15 * 60) { return today }
        return calendar.date(byAdding: .day, value: 1, to: now).flatMap { departure.date(on: $0, calendar: calendar) }
    }
}

/// „heute“, „morgen“ oder der Wochentag.
func relativeDay(_ date: Date, now: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) { return "heute" }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
        return "morgen"
    }
    return Weekday(date: date, calendar: calendar).fullName
}

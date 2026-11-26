// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Verbindungssuche: Von – Nach – (optionaler Zwischenhalt) – Datum – Uhrzeit.
struct TripSearchView: View {
    /// Von außen (Strecken-Widget) zu öffnende Verbindungssuche.
    @Binding var openRoute: RouteLink?
    /// Verbindung, die nach dem Laden der Ergebnisse gleich geöffnet wird (Widget).
    @State private var pendingTrip: TripTarget?

    // Start/Ziel bleiben über App-Neustarts erhalten.
    @AppStorage("tripSearch.origin") private var originData = Data()
    @AppStorage("tripSearch.destination") private var destinationData = Data()
    /// Sucheinstellungen (Deutschlandticket, Umstiege, Gehgeschwindigkeit, Verkehrsmittel) – bleiben gespeichert.
    @AppStorage("tripSearch.options") private var optionsData = Data()
    @State private var showOptions = false

    @State private var via: Stop?
    @State private var showVia = false
    @State private var time = Date.now
    /// Solange der Nutzer die Zeit nicht angefasst hat, wird beim Suchen „jetzt“ verwendet.
    @State private var timeIsNow = true
    @State private var isArrival = false
    @State private var picking: Field?
    @State private var path: [TripRoute] = []

    private enum Field: String, Identifiable {
        case origin, destination, via
        var id: String { rawValue }
        var title: String {
            switch self {
            case .origin: "Von"
            case .destination: "Nach"
            case .via: "Zwischenhalt"
            }
        }
    }

    private var origin: Stop? { Self.decode(originData) }
    private var destination: Stop? { Self.decode(destinationData) }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    VStack(spacing: 0) {
                        StopField(label: "Von", stop: origin) { picking = .origin }
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        // Auf der Linie zwischen Start und Ziel: Zwischenhalt und Tauschen, nur als Symbole.
                        lineWithButtons
                        if showVia {
                            HStack {
                                StopField(label: "Über", stop: via) { picking = .via }
                                Button {
                                    withAnimation { showVia = false; via = nil }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Zwischenhalt entfernen")
                                // Unter der Stelle, wo vorher „+“ war – nicht direkt am Tausch-Knopf.
                                .frame(width: 32)
                                .padding(.trailing, 42)
                            }
                            .padding(.vertical, 14)
                            separatorLine
                        }
                        StopField(label: "Nach", stop: destination) { picking = .destination }
                            .padding(.top, showVia ? 14 : 4)
                            .padding(.bottom, 14)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                }

                Section {
                    Picker("Zeit gilt für", selection: $isArrival) {
                        Text("Abfahrt").tag(false)
                        Text("Ankunft").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    DatePicker("Datum", selection: timeBinding, displayedComponents: .date)
                    DatePicker("Uhrzeit", selection: timeBinding, displayedComponents: .hourAndMinute)
                } footer: {
                    if !timeIsNow {
                        Button("Auf jetzt zurücksetzen") {
                            time = .now
                            timeIsNow = true
                        }
                        .font(.footnote)
                    }
                }

                Section {
                    Button {
                        showOptions = true
                    } label: {
                        HStack {
                            Label("Optionen", systemImage: "slider.horizontal.3")
                            Spacer()
                            Text(options.summary)
                                .font(.subheadline)
                                .foregroundStyle(options.isStandard ? Color.secondary : Color.accentColor)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Button(action: search) {
                        Text("Verbindungen suchen")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(origin == nil || destination == nil)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Verbindungen")
            .onChange(of: openRoute, initial: true) { _, link in
                guard let link else { return }
                var query = link.query
                // Bei einer bestimmten Verbindung kurz vor deren Abfahrt suchen, damit sie sicher dabei ist.
                if let trip = link.trip { query.time = trip.departure.addingTimeInterval(-120) }
                originData = Self.encode(query.origin)
                destinationData = Self.encode(query.destination)
                pendingTrip = link.trip
                path = [.results(query)]
                openRoute = nil
            }
            // Ein einziges Navigationsziel an der Wurzel – gemischte Ziele setzen den Stack sonst zurück.
            .navigationDestination(for: TripRoute.self) { route in
                switch route {
                case .results(let query):
                    TripResultsView(initialQuery: query, autoOpen: pendingTrip) { trip in
                        pendingTrip = nil
                        path.append(.detail(trip, query))
                    }
                case .detail(let trip, let query): TripDetailView(trip: trip, query: query)
                }
            }
            .sheet(isPresented: $showOptions) {
                TripOptionsSheet(options: Binding(get: { options }, set: { optionsData = Self.encodeOptions($0) }))
            }
            .sheet(item: $picking) { field in
                StopPickerSheet(title: field.title) { stop in
                    switch field {
                    case .origin: originData = Self.encode(stop)
                    case .destination: destinationData = Self.encode(stop)
                    case .via: via = stop
                    }
                }
            }
        }
    }

    /// Trennlinie (bündig mit den Haltestellennamen).
    private var separatorLine: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 1 / 3)
            .padding(.leading, 56)
    }

    /// Trennlinie zwischen „Von“ und dem Rest, rechts darauf die runden Knöpfe.
    private var lineWithButtons: some View {
        separatorLine
            .overlay(alignment: .trailing) {
                HStack(spacing: 10) {
                    if !showVia {
                        circleButton("plus", label: "Zwischenhalt hinzufügen") {
                            withAnimation { showVia = true }
                        }
                    }
                    circleButton("arrow.up.arrow.down", label: "Start und Ziel tauschen") {
                        swap(&originData, &destinationData)
                    }
                    .disabled(origin == nil && destination == nil)
                }
            }
            // Eigene Höhe für die Knöpfe: Die Linie liegt in der Mitte, die Namen darüber und darunter
            // laufen nie unter die Knöpfe – auch nicht bei langen, zweizeiligen Namen.
            .frame(height: 40)
            .zIndex(1)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
                .overlay(Circle().stroke(Color(.separator), lineWidth: 1))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { timeIsNow ? .now : time },
            set: { time = $0; timeIsNow = false }
        )
    }

    private func search() {
        guard let origin, let destination else { return }
        let query = TripQuery(origin: origin, destination: destination,
                              via: showVia ? via : nil,
                              time: timeIsNow ? .now : time,
                              isArrivalTime: isArrival,
                              options: options)
        path = [.results(query)]
    }

    private var options: TripOptions {
        (try? JSONDecoder().decode(TripOptions.self, from: optionsData)) ?? .standard
    }

    private static func encodeOptions(_ options: TripOptions) -> Data {
        (try? JSONEncoder().encode(options)) ?? Data()
    }

    private static func decode(_ data: Data) -> Stop? {
        data.isEmpty ? nil : try? JSONDecoder().decode(Stop.self, from: data)
    }

    private static func encode(_ stop: Stop) -> Data {
        var clean = stop
        clean.distance = nil
        return (try? JSONEncoder().encode(clean)) ?? Data()
    }
}

/// Navigationsziele im Verbindungs-Tab.
enum TripRoute: Hashable {
    case results(TripQuery)
    case detail(Trip, TripQuery)
}

/// Eine Zeile „Von: Pirna, Bahnhof“, die beim Antippen die Haltestellenauswahl öffnet.
private struct StopField: View {
    let label: String
    let stop: Stop?
    let action: () -> Void
    @Environment(\.stopNameStyle) private var style

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                if let stop {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stop.label(style)).foregroundStyle(.primary)
                        if let second = stop.secondaryLine(style) {
                            Text(second).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Haltestelle wählen").foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .accessibilityLabel("\(label): \(stop?.label(style) ?? "keine Haltestelle")")
    }
}

/// Auswahl einer Haltestelle: Suche, Favoriten und Haltestellen in der Nähe.
struct StopPickerSheet: View {
    let title: String
    let onSelect: (Stop) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(FavoritesStore.self) private var favorites
    @Environment(LocationProvider.self) private var location
    @Environment(\.transit) private var transit

    @State private var query = ""
    @State private var results: [Stop] = []
    @State private var message: String?
    @State private var nearby: [Stop] = []
    @State private var nearbyLoaded = false
    @State private var searchActive = true

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    if !favorites.stops.isEmpty {
                        Section("Favoriten") {
                            ForEach(favorites.stops) { row($0) }
                        }
                    }
                    Section("In der Nähe") {
                        if nearby.isEmpty {
                            switch location.status {
                            case .denied:
                                Text("Ohne Standortfreigabe keine Haltestellen in der Nähe – oben suchen.")
                                    .foregroundStyle(.secondary)
                            case .failed:
                                Text("Standort konnte nicht ermittelt werden – oben suchen.").foregroundStyle(.secondary)
                            case .located where nearbyLoaded:
                                Text("Keine Haltestellen in der Nähe gefunden.").foregroundStyle(.secondary)
                            default:
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Standort wird ermittelt …").foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            ForEach(nearby.prefix(5)) { row($0) }
                        }
                    }
                } else if let message {
                    Text(message).foregroundStyle(.secondary)
                } else {
                    ForEach(results) { row($0) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $searchActive,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Haltestelle suchen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .task(id: query) { await search() }
            .task { await loadNearby() }
        }
    }

    private func row(_ stop: Stop) -> some View {
        Button {
            onSelect(stop)
            dismiss()
        } label: {
            StopRow(stop: stop).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; message = nil; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let anchors = [location.coordinate].compactMap { $0 } + favorites.stops.compactMap(\.coordinate)
            results = StopSearchRegion.narrow(try await transit.searchStops(query: q), around: anchors)
            message = results.isEmpty ? "Keine Haltestelle gefunden." : nil
        } catch {
            // Beim Weitertippen wird die laufende Suche abgebrochen – das ist kein Fehler.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            message = error.localizedDescription
        }
    }

    private func loadNearby() async {
        if location.coordinate == nil { await location.refresh() }
        guard let coordinate = location.coordinate else { return }
        nearby = (try? await transit.nearbyStops(around: coordinate)) ?? []
        nearbyLoaded = true
    }
}

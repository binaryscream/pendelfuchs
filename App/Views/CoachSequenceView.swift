// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Wagenreihung am Einstieg einer Fahrt: Bahnsteig senkrecht, Abschnitte links, Wagen in der Mitte, Ausstattung rechts.
struct CoachSequenceView: View {
    let leg: TripLeg

    @Environment(\.dismiss) private var dismiss
    @Environment(\.stopNameStyle) private var style
    @State private var state: LoadState = .loading

    private enum LoadState {
        case loading
        case loaded(CoachSequence)
        case unavailable
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView("Wagenreihung wird geladen …")
                case .loaded(let sequence):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header(sequence)
                            PlatformDiagram(sequence: sequence, color: (leg.mode ?? .train).color)
                            legend
                        }
                        .padding()
                    }
                case .unavailable:
                    ContentUnavailableView("Keine Wagenreihung", systemImage: "train.side.front.car",
                                           description: Text("Für diesen Zug liegt bei der Deutschen Bahn keine Wagenreihung vor."))
                case .failed(let message):
                    ContentUnavailableView("Nicht verfügbar", systemImage: "wifi.exclamationmark",
                                           description: Text(message))
                }
            }
            .navigationTitle("Wagenreihung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .task { await load() }
        }
        .presentationDetents([.large])
    }

    private func header(_ sequence: CoachSequence) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                LineBadge(line: leg.line ?? "?", mode: leg.mode ?? .train, compact: true)
                if let number = leg.trainNumber { Text("Zug \(number)").font(.subheadline.weight(.medium)) }
            }
            if let board = leg.stops.first {
                let platform = sequence.platform.map { " · Gleis \($0)" } ?? ""
                Text("\(board.label(style))\(platform)").font(.headline)
            }
            if sequence.coaches.contains(where: \.doubleDeck) {
                Label("Doppelstockwagen", systemImage: "square.stack.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if sequence.destinations.count > 1 {
                Label("Zug wird geteilt – auf das Ziel am Wagen achten", systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wagen in Fahrtrichtung nicht bekannt – die Abschnitte (A, B, …) stehen am Bahnsteig an den Schildern.")
            Text("Daten: Deutsche Bahn (inoffizielle Schnittstelle), ohne Gewähr.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func load() async {
        do {
            if let sequence = try await DBCoachSequenceProvider().coachSequence(for: leg), !sequence.coaches.isEmpty {
                state = .loaded(sequence)
            } else {
                state = .unavailable
            }
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// Der Bahnsteig von oben nach unten.
private struct PlatformDiagram: View {
    let sequence: CoachSequence
    let color: Color

    private let scale: CGFloat = 2.6          // Punkte je Meter
    private let sectorWidth: CGFloat = 30
    private let coachWidth: CGFloat = 92

    /// Angezeigter Ausschnitt: der Zug mit etwas Rand (Abschnittsbuchstaben stehen im sichtbaren Teil).
    private var range: ClosedRange<Double> {
        (sequence.trainStart - 8)...(sequence.trainEnd + 8)
    }

    private func y(_ meters: Double) -> CGFloat { CGFloat(meters - range.lowerBound) * scale }

    var body: some View {
        let height = y(range.upperBound)
        ZStack(alignment: .topLeading) {
            // Abschnitte
            ForEach(sequence.sectors.filter { $0.end > range.lowerBound && $0.start < range.upperBound }, id: \.name) { sector in
                let top = max(0, y(sector.start)), bottom = min(height, y(sector.end))
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
                    .offset(y: top)
                Text(sector.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: sectorWidth, height: bottom - top)
                    .offset(y: top)
            }

            // Wagen und Beschreibung
            ForEach(sequence.coaches) { coach in
                let top = y(coach.start) + 1.5
                let h = max(18, y(coach.end) - y(coach.start) - 3)
                HStack(alignment: .center, spacing: 12) {
                    CoachShape(coach: coach, color: color)
                        .frame(width: coachWidth, height: h)
                    CoachDetails(coach: coach, showsDestination: sequence.destinations.count > 1)
                }
                .frame(height: h)
                .offset(x: sectorWidth + 10, y: top)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}

private struct CoachShape: View {
    let coach: CoachSequence.Coach
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: coach.kind == .coach ? 8 : 18, style: .continuous)
        ZStack {
            shape.fill(Color(.systemBackground))
            shape.fill(fill)
            shape.stroke(stroke, lineWidth: 1.5)
            if coach.kind == .locomotive || coach.kind == .powerCar {
                Image(systemName: "bolt.fill").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    if let number = coach.number {
                        Text(number).font(.title3.weight(.bold).monospacedDigit())
                    }
                    Text(classText).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if coach.closed {
                shape.fill(Color(.systemBackground).opacity(0.6))
                Text("geschlossen").font(.caption2.weight(.semibold)).foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var classText: String {
        switch (coach.firstClass, coach.secondClass) {
        case (true, true): "1. + 2."
        case (true, false): "1. Kl."
        default: "2. Kl."
        }
    }

    private var fill: Color {
        if coach.kind == .locomotive || coach.kind == .powerCar { return Color(.tertiarySystemFill) }
        return coach.firstClass ? Color.yellow.opacity(0.25) : color.opacity(0.18)
    }

    private var stroke: Color {
        coach.kind == .locomotive || coach.kind == .powerCar ? Color.secondary.opacity(0.4)
            : coach.firstClass ? Color.yellow.opacity(0.9) : color
    }

    private var accessibility: String {
        if coach.kind == .locomotive || coach.kind == .powerCar { return "Lok" }
        return [coach.number.map { "Wagen \($0)" }, "\(classText) Klasse", coach.closed ? "geschlossen" : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

private struct CoachDetails: View {
    let coach: CoachSequence.Coach
    let showsDestination: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if coach.bikes { Image(systemName: "bicycle").accessibilityLabel("Fahrradstellplätze") }
                if coach.wheelchair { Image(systemName: "figure.roll").accessibilityLabel("Rollstuhlplätze") }
                if coach.quietZone { Image(systemName: "speaker.slash").accessibilityLabel("Ruhebereich") }
                if coach.familyZone { Image(systemName: "figure.and.child.holdinghands").accessibilityLabel("Familienbereich") }
                if coach.dining { Image(systemName: "fork.knife").accessibilityLabel("Bordrestaurant") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if coach.kind == .locomotive || coach.kind == .powerCar {
                Text("Lok").font(.caption).foregroundStyle(.secondary)
            }
            if showsDestination, let destination = coach.destination {
                Text("→ \(destination)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

// Zeitleiste einer Fahrt: senkrechte Leiste mit Punkten je Halt. Der bereits gefahrene Teil ist in der
// Linienfarbe ausgefüllt, ein Fahrzeug-Symbol zeigt die aktuelle (geschätzte) Position zwischen zwei Halten.

/// Füllstand der Leiste in einer Zeile.
struct RailState: Equatable {
    /// Anteil der oberen Hälfte (vom vorigen Halt kommend), der schon gefahren ist (0…1).
    var top: Double = 0
    /// Anteil der unteren Hälfte (zum nächsten Halt hin), der schon gefahren ist (0…1).
    var bottom: Double = 0
    var dotPassed = false
    /// Fahrzeug in dieser Zeile: Lage 0 (oben) … 1 (unten).
    var vehicleAt: Double?

    /// Zustand für Halt `index` von `count` bei gegebenem Fortschritt.
    static func forStop(_ index: Int, of count: Int, progress: RideProgress) -> RailState {
        switch progress {
        case .notStarted:
            return RailState()
        case .finished:
            return RailState(top: 1, bottom: 1, dotPassed: true)
        case .underway(let passed, let fraction):
            var state = RailState()
            state.dotPassed = index <= passed
            state.top = index <= passed ? 1 : 0
            state.bottom = index < passed ? 1 : 0
            if index == passed {
                // Erste Hälfte des Abschnitts liegt unten in dieser Zeile …
                state.bottom = min(1, fraction * 2)
                if fraction < 0.5 { state.vehicleAt = 0.5 + fraction }
            } else if index == passed + 1 {
                // … die zweite Hälfte oben in der Zeile des nächsten Halts.
                state.top = max(0, fraction * 2 - 1)
                if fraction >= 0.5 { state.vehicleAt = fraction - 0.5 }
            }
            return state
        }
    }
}

/// Die gezeichnete Leiste (wird links neben jede Zeile gesetzt).
struct RailView: View {
    let state: RailState
    let color: Color
    var isFirst = false
    var isLast = false
    var emphasized = false
    var showDot = true
    var vehicleSymbol: String = "circle.fill"

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let mid = height / 2
            let x = geo.size.width / 2
            ZStack {
                // Etwas über den Zeilenrand hinaus, damit zwischen den Listenzeilen keine Haarlinie bleibt.
                if !isFirst {
                    segment(from: -1.5, to: mid, filled: state.top, x: x)
                }
                if !isLast {
                    segment(from: mid, to: height + 1.5, filled: state.bottom, x: x)
                }
                if showDot {
                    let size: CGFloat = emphasized ? 16 : 11
                    Circle()
                        .fill(state.dotPassed ? color : Color(.systemBackground))
                        .overlay(Circle().stroke(color, lineWidth: emphasized ? 3.5 : 2.5))
                        .frame(width: size, height: size)
                        .position(x: x, y: mid)
                }
                if let vehicleAt = state.vehicleAt {
                    Image(systemName: vehicleSymbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(color, in: Circle())
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .position(x: x, y: min(max(height * vehicleAt, 12), height - 12)) // nicht am Zeilenrand abschneiden
                        .accessibilityLabel("Aktuelle Position")
                }
            }
        }
        .frame(width: 28)
        // Zwischen den Sekundenschritten gleiten statt springen (Fahrzeug und gefüllte Strecke).
        .animation(.linear(duration: 1), value: state)
    }

    private func segment(from start: CGFloat, to end: CGFloat, filled: Double, x: CGFloat) -> some View {
        let split = start + (end - start) * filled
        return ZStack {
            Path { $0.move(to: CGPoint(x: x, y: start)); $0.addLine(to: CGPoint(x: x, y: end)) }
                .stroke(color.opacity(0.25), lineWidth: 5)
            if filled > 0 {
                Path { $0.move(to: CGPoint(x: x, y: start)); $0.addLine(to: CGPoint(x: x, y: split)) }
                    .stroke(color, lineWidth: 5)
            }
        }
    }
}

/// Ein Halt in der Zeitleiste.
struct TimelineStopRow: View {
    @Environment(\.stopNameStyle) private var style
    let stop: TripStop
    let time: TimePoint?
    let mode: TransportMode
    let rail: RailState
    var isFirst = false
    var isLast = false
    var emphasized = false
    var showPlace = false
    /// Hervorhebung, z. B. „Hier“ für die Haltestelle des Abfahrtsmonitors.
    var badge: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RailView(state: rail, color: mode.color, isFirst: isFirst, isLast: isLast,
                     emphasized: emphasized || badge != nil, vehicleSymbol: mode.symbolName)

            Group {
                if let time { TimePointText(point: time) } else { Text("–") }
            }
            .frame(width: 70, alignment: .leading)
            .font(emphasized ? .body.weight(.semibold) : .subheadline)
            .padding(.vertical, emphasized ? 12 : 8)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(stop.label(style))
                        .font(emphasized || badge != nil ? .body.weight(.semibold) : .subheadline)
                        .strikethrough(stop.isCancelled)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(mode.color, in: Capsule())
                    }
                }
                if emphasized || showPlace, let second = stop.secondaryLine(style) {
                    Text(second).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if emphasized, let platform = stop.platform, !platform.isEmpty {
                if stop.platformChanged {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(mode.platformLabel(platform))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange, in: Capsule())
                        Text("statt \(stop.scheduledPlatform ?? "")").font(.caption2).foregroundStyle(.orange)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Gleiswechsel: \(mode.platformLabel(platform)) statt \(stop.scheduledPlatform ?? "")")
                } else {
                    Text(mode.platformLabel(platform))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        // Erste/letzte Zeile mit etwas Luft zum Kartenrand (dort endet die Leiste ohnehin am Punkt).
        .padding(.top, isFirst ? 4 : 0)
        .padding(.bottom, isLast ? 6 : 0)
        // Mindesthöhe ≥ Standard-Zeilenhöhe der Liste, sonst entstehen Lücken in der Leiste.
        .frame(minHeight: 48)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(stop.isCancelled ? AnyShapeStyle(.red)
                         : rail.dotPassed && !emphasized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .timelineRow()
        .accessibilityElement(children: .combine)
        .accessibilityValue(rail.dotPassed ? "passiert" : "")
    }
}

/// Zeile „5 Zwischenhalte“ zum Auf-/Zuklappen – die Leiste läuft durch.
struct TimelineToggleRow: View {
    let title: String
    let mode: TransportMode
    let rail: RailState
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                RailView(state: rail, color: mode.color, showDot: false, vehicleSymbol: mode.symbolName)
                Text(title).font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 48)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .timelineRow()
    }
}

/// Ob die Zwischenhalte in den Fahrtdetails aufgeklappt sind (Einstellung).
enum StopListExpansion: String, CaseIterable, Identifiable {
    case collapsed, whileRiding, expanded

    static let storageKey = "display.stopListExpansion"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .collapsed: "Zugeklappt"
        case .whileRiding: "Während der Fahrt aufgeklappt"
        case .expanded: "Immer aufgeklappt"
        }
    }
}

/// Alle Halte einer Fahrt als Zeitleiste (Zwischenhalte aufklappbar).
struct RideTimeline: View {
    let leg: TripLeg
    let now: Date
    /// Haltestelle, die hervorgehoben wird (Abfahrtsmonitor) – dann immer aufgeklappt.
    var highlightedStopIndex: Int?
    @State private var expanded: Bool?
    @AppStorage(StopListExpansion.storageKey) private var expansion = StopListExpansion.collapsed

    var body: some View {
        let progress = leg.progress(at: now)
        let mode = leg.mode ?? .other
        let count = leg.stops.count
        // Vorgabe aus den Einstellungen; mit hervorgehobenem Halt („Hier“) immer aufgeklappt. Antippen überstimmt beides.
        let riding = { if case .underway = progress { true } else { false } }()
        let automatic = highlightedStopIndex != nil || expansion == .expanded || (expansion == .whileRiding && riding)
        let isExpanded = expanded ?? automatic

        ForEach(Array(leg.stops.enumerated()), id: \.offset) { index, stop in
            let isEnd = index == 0 || index == count - 1
            if isEnd || isExpanded {
                TimelineStopRow(
                    stop: stop,
                    time: index == 0 ? stop.departure : index == count - 1 ? stop.arrival : (stop.departure ?? stop.arrival),
                    mode: mode,
                    rail: .forStop(index, of: count, progress: progress),
                    isFirst: index == 0, isLast: index == count - 1,
                    emphasized: isEnd,
                    showPlace: !isEnd && stop.place != leg.stops.last?.place,
                    badge: index == highlightedStopIndex ? "Hier" : nil
                )
            }
            if index == 0, count > 2 {
                TimelineToggleRow(title: summary, mode: mode,
                                  rail: collapsedRail(progress: progress, count: count, expanded: isExpanded),
                                  isExpanded: Binding(get: { isExpanded }, set: { expanded = $0 }))
            }
        }
    }

    private var summary: String {
        let between = leg.stops.count - 2
        var text = between == 1 ? "1 Zwischenhalt" : "\(between) Zwischenhalte"
        if let minutes = leg.durationMinutes, minutes > 0 { text += " · \(minutes) min" }
        return text
    }

    /// Leiste der Klapp-Zeile: dazwischen liegende Strecke, ggf. mit Fahrzeug in der Mitte.
    private func collapsedRail(progress: RideProgress, count: Int, expanded: Bool) -> RailState {
        // Aufgeklappt liegt die Klapp-Zeile zwischen dem ersten und zweiten Halt.
        if expanded {
            let first = RailState.forStop(0, of: count, progress: progress)
            let second = RailState.forStop(1, of: count, progress: progress)
            let filled = first.bottom >= 1 && second.top > 0 ? 1.0 : (first.bottom >= 1 ? 0.5 : 0)
            return RailState(top: filled, bottom: second.top > 0 ? 1 : 0)
        }
        switch progress {
        case .notStarted: return RailState()
        case .finished: return RailState(top: 1, bottom: 1)
        case .underway(let passed, _):
            if passed >= count - 2 { return RailState(top: 1, bottom: 1) }
            return RailState(top: 1, bottom: 0, vehicleAt: 0.5)
        }
    }
}

extension View {
    /// Listenzeile ohne Trennlinie und ohne Innenabstand oben/unten, damit die Leiste durchgehend aussieht.
    func timelineRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 16))
    }
}

// MARK: - Statuszeilen (auch im Abfahrtsmonitor genutzt)

/// „Nächster Halt: Hauptbahnhof · in 3 min“ mit Fortschrittsbalken bis dorthin.
struct NextStopRow: View {
    @Environment(\.stopNameStyle) private var style
    let next: TripStop
    let fraction: Double
    let mode: TransportMode
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill").foregroundStyle(mode.color)
                Text("Nächster Halt: \(next.label(style))").font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let time = (next.arrival ?? next.departure)?.expectedTime {
                    Text(minutesUntil(time, now: now)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: fraction).tint(mode.color)
                .animation(.linear(duration: 1), value: fraction)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Gesamtfortschritt: vor der Abfahrt, unterwegs, angekommen.
struct TripStatusView: View {
    @Environment(\.stopNameStyle) private var style
    let trip: Trip
    let now: Date

    private func message(for disruption: TripDisruption) -> String {
        switch disruption {
        case .rideCancelled(let line):
            trip.rides.count > 1 ? "\(line ?? "Eine Fahrt") fällt aus" : "Diese Fahrt fällt aus"
        case .boardingCancelled(_, let stop):
            "Einstieg entfällt: \(stop.label(style))"
        case .alightingCancelled(_, let stop):
            "Ausstieg entfällt: \(stop.label(style))"
        case .connectionMissed(let line, let stop):
            "Anschluss \(line ?? "") verpasst in \(stop.label(style))"
        }
    }

    var body: some View {
        let departure = trip.departure.expectedTime
        let arrival = trip.arrival.expectedTime
        if let disruption = trip.disruption {
            // Nicht fahrbar: kein Fortschritt und keine Abfahrtszeit, sondern ein klarer Hinweis.
            Label(message(for: disruption), systemImage: "xmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
        } else if now >= arrival {
            Label("Angekommen", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
        } else if let progress = trip.overallProgress(at: now) {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(trip.rides.first?.mode?.color ?? .accentColor)
                    .animation(.linear(duration: 1), value: progress)
                Text("Unterwegs · noch \(remaining(until: arrival, now: now)) bis zur Ankunft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        } else if departure.timeIntervalSince(now) < 3 * 3600 {
            Label("Abfahrt \(minutesUntil(departure, now: now))", systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// „5 min“, „1 h 20 min“ (aufgerundet, mindestens 1 min).
func remaining(until date: Date, now: Date) -> String {
    let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
}

/// „in 5 min“ bzw. „jetzt“.
func minutesUntil(_ date: Date, now: Date) -> String {
    date <= now ? "jetzt" : "in \(remaining(until: date, now: now))"
}

extension TripDisruption {
    /// Kurzer Hinweis für Listen („S1 fällt aus“, „Anschluss verpasst“).
    var shortText: String {
        switch self {
        case .rideCancelled(let line): "\(line ?? "Fahrt") fällt aus"
        case .boardingCancelled: "Einstieg entfällt"
        case .alightingCancelled: "Ausstieg entfällt"
        case .connectionMissed(let line, _): "Anschluss \(line ?? "") verpasst"
        }
    }

    /// Ein Wort für ein Statusschild.
    var badgeText: String {
        switch self {
        case .rideCancelled: "Fällt aus"
        case .boardingCancelled, .alightingCancelled: "Halt entfällt"
        case .connectionMissed: "Anschluss weg"
        }
    }
}

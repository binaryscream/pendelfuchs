// SPDX-License-Identifier: GPL-3.0-or-later

import ActivityKit
import FahrplanKit
import SwiftUI
import WidgetKit

/// Sperrbildschirm und Dynamic Island für eine laufende Fahrt.
///
/// Countdown und Fortschrittsbalken laufen über `Text(timerInterval:)` bzw. `ProgressView(timerInterval:)`
/// selbstständig weiter – die App muss nur bei geänderten Echtzeitdaten aktualisieren.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LockScreenView(saved: context.attributes.saved, state: context.state, isStale: context.isStale)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let info = PhaseInfo(state: context.state, now: .now)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let ride = info.ride {
                        LineBadge(line: ride.line, mode: ride.mode)
                            .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(target: info.target)
                        .font(.headline)
                        .frame(minWidth: 96, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(info.headline).font(.headline).lineLimit(1)
                        Text(context.state.note ?? info.subline).font(.caption)
                            .foregroundStyle(context.state.note == nil ? Color.secondary : Color.orange).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TripProgress(state: context.state)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
            } compactLeading: {
                if let ride = info.ride {
                    LineBadge(line: ride.line, mode: ride.mode, compact: true)
                }
            } compactTrailing: {
                // Kreis, der sich bis zum Ziel der aktuellen Phase (Abfahrt bzw. Ankunft) schließt.
                PhaseRing(info: info, hasProblem: context.state.isCancelled)
                    .frame(width: 22, height: 22)
            } minimal: {
                PhaseRing(info: info, hasProblem: context.state.isCancelled)
                    .frame(width: 22, height: 22)
            }
            .keylineTint(info.ride?.mode.color ?? .accentColor)
        }
    }
}

// MARK: - Sperrbildschirm

private struct LockScreenView: View {
    private let style = StopNameStyle.current
    let saved: SavedTrip
    let state: TripActivityState
    let isStale: Bool

    var body: some View {
        let info = PhaseInfo(state: state, now: .now)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(saved.title(style: style), systemImage: "tram.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                // Immer sichtbar, damit „Aktualisieren“ eine Wirkung zeigt; orange, wenn die Daten alt sind.
                Text("Stand \(state.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(state.updatedAt < .now.addingTimeInterval(-15 * 60) ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Button(intent: RefreshTripActivityIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel("Aktualisieren")
                Button(intent: EndTripActivityIntent(id: saved.id)) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel("Live-Aktivität beenden")
            }
            // Die Knöpfe ragen über die Textzeile hinaus, ohne die Aktivität höher zu machen.
            .frame(height: 18)

            HStack(alignment: .center, spacing: 12) {
                if let ride = info.ride {
                    LineBadge(line: ride.line, mode: ride.mode)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.headline).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    Text(info.subline).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                // Countdown bekommt eine feste Breite, die Überschrift weicht aus.
                // Achtung: KEIN .fixedSize() – selbstaktualisierende Texte haben keine feste Idealbreite,
                // das bringt den Live-Aktivitäts-Renderer von iOS zum Absturz (LayoutSubview.place).
                VStack(alignment: .trailing, spacing: 0) {
                    CountdownText(target: info.target)
                        .font(.title3.weight(.bold))
                    Text(info.countdownLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 112, alignment: .trailing)
            }

            if state.note == nil, let ride = info.ride, let platform = ride.fromPlatform,
               let scheduled = ride.fromScheduledPlatform, state.phase(at: .now) != .arrived {
                Label("Gleiswechsel: \(ride.mode.platformLabel(platform)) statt \(scheduled)",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            if let note = state.note {
                Label(note, systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            TripProgressBar(state: state)
            RideChain(state: state)
        }
    }
}

/// Fortschrittsbalken über die ganze Fahrt (läuft selbstständig weiter).
private struct TripProgressBar: View {
    let state: TripActivityState

    var body: some View {
        let start = state.departure.expectedTime
        let end = max(state.arrival.expectedTime, start.addingTimeInterval(60))
        ProgressView(timerInterval: start...end, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .tint(state.rides.first?.mode.color ?? .accentColor)
        .accessibilityLabel("Fortschritt der Fahrt")
    }
}

/// Die noch offenen Fahrten mit ihren Zeiten, z. B. „S1 07:06 Pirna → 07:28 Dresden Hbf“ und darunter der Bus –
/// so sieht man nach der ersten Fahrt sofort, wann die zweite fährt.
private struct RideChain: View {
    private let style = StopNameStyle.current
    let state: TripActivityState

    var body: some View {
        // Erledigte Fahrten fallen heraus (iOS zeichnet die Aktivität an jedem Phasenwechsel neu);
        // nach der Ankunft bleibt die letzte Fahrt stehen.
        let open = state.rides.filter { $0.arrival.expectedTime > .now }
        let shown = Array((open.isEmpty ? Array(state.rides.suffix(1)) : open).prefix(3))
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, ride in
                if index > 0, let previous = shown[safe: index - 1] {
                    let minutes = Int((ride.departure.expectedTime.timeIntervalSince(previous.arrival.expectedTime) / 60).rounded())
                    Text("Umstieg · \(max(0, minutes)) min")
                        .font(.caption2)
                        .foregroundStyle(minutes < 0 ? Color.red : Color.secondary)
                        .padding(.leading, 38)
                }
                HStack(spacing: 6) {
                    LineBadge(line: ride.line, mode: ride.mode, compact: true)
                        .frame(width: 32)
                    TimeLabel(prefix: "", point: ride.departure)
                        .fontWeight(.semibold)
                    Text(ride.fromLabel(style)).lineLimit(1)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    TimeLabel(prefix: "", point: ride.arrival)
                        .fontWeight(.semibold)
                    Text(ride.toLabel(style)).lineLimit(1)
                }
                .font(.caption)
                .minimumScaleFactor(0.75)
                .strikethrough(ride.isCancelled, color: .red)
                // Als ein Satz vorlesen statt in losen Bruchstücken; ein Ausfall wird ausgesprochen.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(ride))
            }
        }
    }
}

private extension RideChain {
    /// „S1, ab 7:06 Pirna Bahnhof, an 7:28 Dresden Hbf“ – mit Ausfall bzw. Verspätung.
    func spoken(_ ride: TripActivityState.Ride) -> String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        var text = "\(ride.line), ab \(ride.departure.expectedTime.formatted(time)) \(ride.fromLabel(style)), "
            + "an \(ride.arrival.expectedTime.formatted(time)) \(ride.toLabel(style))"
        if ride.isCancelled {
            text += ", fällt aus"
        } else if let delay = ride.departure.delayMinutes, delay > 0 {
            text += ", \(delay) \(delay == 1 ? "Minute" : "Minuten") Verspätung"
        }
        return text
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Fortschrittsbalken über die gesamte Fahrt plus Abfahrt/Linienkette/Ankunft.
private struct TripProgress: View {
    let state: TripActivityState

    var body: some View {
        VStack(spacing: 6) {
            let start = state.departure.expectedTime
            let end = max(state.arrival.expectedTime, start.addingTimeInterval(60))
            ProgressView(timerInterval: start...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(state.rides.first?.mode.color ?? .accentColor)
            .accessibilityLabel("Fortschritt der Fahrt")

            HStack(spacing: 6) {
                TimeLabel(prefix: "ab", point: state.departure)
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    ForEach(Array(state.rides.enumerated()), id: \.offset) { index, ride in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        LineBadge(line: ride.line, mode: ride.mode, compact: true)
                    }
                }
                Spacer(minLength: 4)
                TimeLabel(prefix: "an", point: state.arrival)
            }
            .font(.caption)
        }
    }
}

private struct TimeLabel: View {
    @AppStorage(DelayDisplay.storageKey, store: AppGroup.defaults) private var style = DelayDisplay.badge
    let prefix: String
    let point: TimePoint

    var body: some View {
        let delay = point.delayMinutes ?? 0
        HStack(spacing: 3) {
            if style == .actual, delay != 0 {
                // Tatsächliche Zeit, Verspätung eingerechnet
                Text("\(prefix.isEmpty ? "" : prefix + " ")\(point.expectedTime.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit()
                    .foregroundStyle(delay >= 3 ? .red : .orange)
            } else {
                Text("\(prefix.isEmpty ? "" : prefix + " ")\(point.scheduledTime.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit()
                if delay != 0 {
                    Text(delay > 0 ? "+\(delay)" : "\(delay)")
                        .fontWeight(.semibold)
                        .foregroundStyle(delay >= 3 ? .red : .orange)
                        .accessibilityLabel(delay > 0 ? "\(delay) Minuten Verspätung" : "\(-delay) Minuten früher")
                }
            }
        }
    }
}

/// Ring, der sich selbstständig bis zum Ziel der aktuellen Phase schließt (Dynamic Island). In der Mitte das
/// Verkehrsmittel; fehlt ein Ziel (angekommen), ist der Ring voll mit Haken.
private struct PhaseRing: View {
    let info: PhaseInfo
    /// Eine Fahrt fällt aus – dann warnt auch die kleine Ansicht, statt einen normalen Ring zu zeigen.
    var hasProblem = false

    var body: some View {
        let tint = info.ride?.mode.color ?? Color.accentColor
        if hasProblem {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 16)).foregroundStyle(.red)
                .accessibilityLabel("Fahrt fällt aus")
        } else if let range = info.ringRange, range.upperBound > .now {
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(tint)
            .accessibilityLabel(info.isRiding ? "Unterwegs" : "Bis zur Abfahrt")
            .overlay {
                Image(systemName: info.isRiding ? "tram.fill" : "clock.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)
            }
        } else {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(tint)
                .accessibilityLabel("Angekommen")
        }
    }
}

/// Selbstständig weiterlaufender Countdown: „in 18 Min.“ – und nach dem Zeitpunkt „vor 2 Min.“.
///
/// iOS zeichnet die Aktivität ohne App nur einmal neu (zum `staleDate`). Bleibt sie danach in einer Phase
/// stehen, zählte die frühere Anzeige (`.relative`) nach dem Ziel unbemerkt wieder hoch; „vor … Min.“ zeigt
/// dagegen klar, dass der Zeitpunkt vorbei ist. Eine Uhr mit Sekunden zeigt auf dem Sperrbildschirm „––“.
private struct CountdownText: View {
    let target: Date?

    var body: some View {
        if let target, target > .now {
            Text(.currentDate, format: .reference(to: target, allowedFields: [.hour, .minute], maxFieldCount: 2))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
        } else {
            Text(target == nil ? "✓" : "jetzt")
        }
    }
}

// MARK: - Texte je Phase

/// Überschriften und Countdown-Ziel für die aktuelle Phase der Fahrt.
private struct PhaseInfo {
    let ride: TripActivityState.Ride?
    let target: Date?
    let headline: String
    let subline: String
    let countdownLabel: String
    /// Zeitraum, über den sich der Ring der Dynamic Island schließt.
    let ringRange: ClosedRange<Date>?
    let isRiding: Bool

    init(state: TripActivityState, now: Date) {
        let style = StopNameStyle.current
        ride = state.focusRide(at: now)
        target = state.countdownTarget(at: now)

        switch state.phase(at: now) {
        case .riding(let index):
            let r = state.rides[index]
            ringRange = r.departure.expectedTime...max(r.arrival.expectedTime, r.departure.expectedTime.addingTimeInterval(60))
            isRiding = true
        case .waiting, .transfer:
            if let target {
                // Die letzten 15 Minuten vor der Abfahrt (höchstens seit der letzten Aktualisierung).
                let start = max(state.updatedAt, target.addingTimeInterval(-15 * 60))
                ringRange = min(start, target.addingTimeInterval(-60))...target
            } else {
                ringRange = nil
            }
            isRiding = false
        case .arrived:
            ringRange = nil
            isRiding = false
        }

        guard let ride else {
            headline = "Keine Daten"; subline = ""; countdownLabel = ""
            return
        }
        let platform = ride.fromPlatform.map { value in
            // Gleiswechsel gleich in der Überschrift: „Gl. 3 statt 1“.
            " · \(ride.mode.platformLabel(value))" + (ride.fromScheduledPlatform.map { " statt \($0)" } ?? "")
        } ?? ""
        let direction = ride.direction.map { "Richtung \($0)" } ?? ""

        if ride.isCancelled {
            headline = "\(ride.line) fällt aus"
            subline = "Bitte Alternative suchen"
            countdownLabel = ""
            return
        }

        switch state.phase(at: now) {
        case .waiting:
            headline = "\(ride.fromLabel(style))\(platform)"
            subline = direction
            countdownLabel = "Abfahrt"
        case .transfer:
            headline = "Umstieg in \(ride.line)"
            subline = "\(ride.fromLabel(style))\(platform)"
            countdownLabel = "Abfahrt"
        case .riding:
            headline = "Bis \(ride.toLabel(style))"
            subline = direction
            countdownLabel = "Ausstieg"
        case .arrived:
            headline = "Angekommen"
            subline = ride.toLabel(style)
            countdownLabel = ""
        }
    }
}

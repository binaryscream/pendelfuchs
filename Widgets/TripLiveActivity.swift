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
                .padding(16)
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
                        Text(info.subline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                PhaseRing(info: info)
                    .frame(width: 22, height: 22)
            } minimal: {
                PhaseRing(info: info)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(saved.title(style: style), systemImage: "tram.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if isStale {
                    Text("Stand \(state.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

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

            TripProgress(state: state)
        }
    }
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
                Text("\(prefix) \(point.expectedTime.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit()
                    .foregroundStyle(delay >= 3 ? .red : .orange)
            } else {
                Text("\(prefix) \(point.scheduledTime.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit()
                if delay != 0 {
                    Text(delay > 0 ? "+\(delay)" : "\(delay)")
                        .fontWeight(.semibold)
                        .foregroundStyle(delay >= 3 ? .red : .orange)
                }
            }
        }
    }
}

/// Ring, der sich selbstständig bis zum Ziel der aktuellen Phase schließt (Dynamic Island). In der Mitte das
/// Verkehrsmittel; fehlt ein Ziel (angekommen), ist der Ring voll mit Haken.
private struct PhaseRing: View {
    let info: PhaseInfo

    var body: some View {
        let tint = info.ride?.mode.color ?? Color.accentColor
        if let range = info.ringRange, range.upperBound > .now {
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(tint)
            .overlay {
                Image(systemName: info.isRiding ? "tram.fill" : "clock.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)
            }
        } else {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(tint)
        }
    }
}

/// Selbstständig weiterlaufender Countdown.
/// Über zwei Minuten „18 Min.“ (eine Uhr wie „17:57“ würde man für eine Uhrzeit halten),
/// in den letzten zwei Minuten sekundengenau „1:59“.
private struct CountdownText: View {
    let target: Date?

    var body: some View {
        if let target, target > .now {
            Group {
                if target.timeIntervalSinceNow > 120 {
                    // Nur eine Einheit („23 Stunden“ bzw. „45 Minuten“), damit es in jede Ansicht passt.
                    Text(.currentDate, format: .offset(to: target, allowedFields: [.hour, .minute],
                                                       maxFieldCount: 1, sign: .never))
                } else {
                    Text(timerInterval: Date.now...target, countsDown: true)
                }
            }
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
        let platform = ride.fromPlatform.map { " · \(ride.mode.platformLabel($0))" } ?? ""
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
            countdownLabel = "bis Abfahrt"
        case .transfer:
            headline = "Umstieg in \(ride.line)"
            subline = "\(ride.fromLabel(style))\(platform)"
            countdownLabel = "bis Abfahrt"
        case .riding:
            headline = "Bis \(ride.toLabel(style))"
            subline = direction
            countdownLabel = "bis Ausstieg"
        case .arrived:
            headline = "Angekommen"
            subline = ride.toLabel(style)
            countdownLabel = ""
        }
    }
}

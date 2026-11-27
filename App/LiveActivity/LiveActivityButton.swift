// SPDX-License-Identifier: GPL-3.0-or-later

import FahrplanKit
import SwiftUI

/// Startet bzw. beendet die Live-Aktivität für eine Fahrt.
struct LiveActivityButton: View {
    let saved: SavedTrip
    /// Bereits geladene Verbindung, falls vorhanden (spart eine Abfrage).
    var knownTrip: Trip?
    /// Zweite Kennung derselben Fahrt: Wurde die Aktivität vor dem Merken gestartet, läuft sie unter der
    /// vorläufigen Kennung weiter – der Knopf muss sie trotzdem finden und beenden.
    var otherID: UUID?

    @State private var isRunning = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            HStack {
                Label(isRunning ? "Live-Aktivität beenden" : "Live-Aktivität starten",
                      systemImage: isRunning ? "stop.circle" : "livephoto")
                Spacer()
                if isWorking { ProgressView() }
            }
        }
        .disabled(isWorking)
        .tint(isRunning ? .red : .accentColor)
        .sensoryFeedback(.impact, trigger: isRunning)
        // Laufend nachsehen: Die Aktivität kann auch vom Sperrbildschirm aus oder von selbst enden.
        .task(id: saved.id) {
            while !Task.isCancelled {
                if !isWorking { isRunning = runsNow }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .alert("Live-Aktivität", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func toggle() async {
        isWorking = true
        defer { isWorking = false }
        let manager = TripActivityManager.shared
        if isRunning {
            await manager.end(saved.id)
            if let otherID { await manager.end(otherID) }
        } else {
            do {
                try await manager.start(saved, knownTrip: knownTrip)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        isRunning = runsNow
    }

    private var runsNow: Bool {
        let manager = TripActivityManager.shared
        return manager.isRunning(saved.id) || (otherID.map(manager.isRunning) ?? false)
    }
}

/// Erklärt, wie man die Live-Aktivität automatisch per Kurzbefehle startet.
struct LiveActivityAutomationHint: View {
    let saved: SavedTrip

    var body: some View {
        if saved.isRegular {
            let start = TimeOfDay(hour: (saved.departure.minutesSinceMidnight - 20 + 1440) % 1440 / 60,
                                  minute: (saved.departure.minutesSinceMidnight - 20 + 1440) % 60)
            Text("Automatisch starten: In der Kurzbefehle-App unter „Automation“ eine neue Automation „Tageszeit“ anlegen (z. B. \(start.formatted), \(saved.weekdays.summary)), „Sofort ausführen“ wählen und die Aktion „Live-Aktivität starten“ von Pendelfuchs mit dieser Fahrt hinzufügen.")
        } else {
            Text("Zeigt die Fahrt mit Countdown und Echtzeit auf dem Sperrbildschirm und in der Dynamic Island.")
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Bremst die Live-Tests, damit der ehrenamtlich betriebene Dienst Transitous nicht mit parallelen
/// Anfragen überrollt wird (sonst antwortet er mit HTTP 429).
actor LiveThrottle {
    static let shared = LiveThrottle()
    private var next = Date.distantPast

    func wait(seconds: Double = 2.5) async {
        let now = Date.now
        let start = max(now, next)
        next = start.addingTimeInterval(seconds)
        let delay = start.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
    }
}

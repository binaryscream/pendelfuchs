// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import FahrplanKit

private let berlin: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    berlin.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

@Suite struct RouteDirectionTests {
    let turn = TimeOfDay(hour: 14, minute: 0)

    @Test func automaticDirectionFollowsTurnTime() {
        #expect(!RouteDirection.isReversed(at: date(24, 6, 30), turnAt: turn, state: nil, calendar: berlin))
        #expect(!RouteDirection.isReversed(at: date(24, 13, 59), turnAt: turn, state: nil, calendar: berlin))
        #expect(RouteDirection.isReversed(at: date(24, 14, 0), turnAt: turn, state: nil, calendar: berlin))
        #expect(RouteDirection.isReversed(at: date(24, 23, 30), turnAt: turn, state: nil, calendar: berlin))
        // am nächsten Morgen wieder Hinweg
        #expect(!RouteDirection.isReversed(at: date(25, 6, 30), turnAt: turn, state: nil, calendar: berlin))
    }

    @Test func withoutTurnTimeAlwaysForward() {
        #expect(!RouteDirection.isReversed(at: date(24, 20), turnAt: nil, state: nil, calendar: berlin))
    }

    @Test func swapFlipsOnlyCurrentPeriod() {
        let morning = date(24, 8)
        let state = RouteDirection.toggled(at: morning, turnAt: turn, state: nil, calendar: berlin)
        #expect(RouteDirection.isReversed(at: morning, turnAt: turn, state: state, calendar: berlin))
        #expect(RouteDirection.isReversed(at: date(24, 13, 59), turnAt: turn, state: state, calendar: berlin))
        // Nach der Wendezeit gilt wieder die Automatik (Rückweg), der Tausch vom Morgen ist erledigt.
        #expect(RouteDirection.isReversed(at: date(24, 15), turnAt: turn, state: state, calendar: berlin))
        #expect(!RouteDirection.isReversed(at: date(25, 8), turnAt: turn, state: state, calendar: berlin))
    }

    @Test func swappingTwiceRestoresDirection() {
        let t = date(24, 8)
        let once = RouteDirection.toggled(at: t, turnAt: turn, state: nil, calendar: berlin)
        let twice = RouteDirection.toggled(at: t, turnAt: turn, state: once, calendar: berlin)
        #expect(!RouteDirection.isReversed(at: t, turnAt: turn, state: twice, calendar: berlin))
    }

    @Test func swapAfterTurnShowsOutwardTrip() {
        let evening = date(24, 17)
        let state = RouteDirection.toggled(at: evening, turnAt: turn, state: nil, calendar: berlin)
        #expect(!RouteDirection.isReversed(at: evening, turnAt: turn, state: state, calendar: berlin))
    }

    @Test func nextChange() {
        #expect(RouteDirection.nextChange(after: date(24, 8), turnAt: turn, calendar: berlin) == date(24, 14))
        #expect(RouteDirection.nextChange(after: date(24, 15), turnAt: turn, calendar: berlin) == date(25, 0))
        #expect(RouteDirection.nextChange(after: date(24, 15), turnAt: nil, calendar: berlin) == date(25, 0))
    }
}

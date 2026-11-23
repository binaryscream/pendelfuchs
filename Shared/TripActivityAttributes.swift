// SPDX-License-Identifier: GPL-3.0-or-later

import ActivityKit
import FahrplanKit

/// Live-Aktivität für eine (gemerkte oder einmalige) Fahrt.
/// Die feste Fahrt steckt in den Attributen, die veränderlichen Echtzeitdaten im ContentState.
struct TripActivityAttributes: ActivityAttributes {
    typealias ContentState = TripActivityState

    /// Die Fahrt samt Start/Ziel/Linien – zum Wiederfinden bei Aktualisierungen.
    var saved: SavedTrip
}

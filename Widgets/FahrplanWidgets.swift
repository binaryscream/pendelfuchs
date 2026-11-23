// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WidgetKit

/// Widget-Erweiterung von Fahrplan XL. Enthält die Live-Aktivität (später auch Home-Screen-Widgets).
@main
struct FahrplanWidgets: WidgetBundle {
    var body: some Widget {
        TripLiveActivity()
    }
}

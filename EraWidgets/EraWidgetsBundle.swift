import WidgetKit
import SwiftUI

@main
struct EraWidgetsBundle: WidgetBundle {
    var body: some Widget {
        EraRecentWidget()
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        EraLiveActivity()
        #endif
    }
}

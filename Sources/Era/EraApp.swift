import SwiftUI
import SwiftData

@main
struct EraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.$modelContext, ModelContainer(defaultSchema: Schema([Track.self, Tag.self, Preset.self])).modelContext)
        }
    }
}

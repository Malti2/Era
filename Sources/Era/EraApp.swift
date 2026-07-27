import SwiftUI
import SwiftData
import MusicKit

@main
struct EraApp: App {
    // SwiftData container
    var container: ModelContainer
    
    init() {
        // Initialize SwiftData container with models
        do {
            container = try ModelContainer(for: [Tag.self, Preset.self])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContext(container.mainContext)
                .background(Color.black.ignoresSafeArea())
        }
    }
}

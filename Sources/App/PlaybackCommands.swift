import SwiftUI

extension Notification.Name {
    /// userInfo["screen"] = AppScreen.rawValue; ContentView wechselt den Tab.
    static let eraSwitchScreen = Notification.Name("era.switchScreen")
    /// Cmd+O: LibraryView oeffnet den Datei-Import.
    static let eraImportMusic = Notification.Name("era.importMusic")
    /// Cmd+N: LibraryView zeigt Playlists und fragt nach einem Namen.
    static let eraNewPlaylist = Notification.Name("era.newPlaylist")
}

// Tab-Wechsel per Tastatur (Mac/iPad): Cmd+1...4 und Cmd+F fuer die Suche.
struct NavigationCommands: Commands {
    private func show(_ screen: AppScreen) {
        NotificationCenter.default.post(name: .eraSwitchScreen, object: nil, userInfo: ["screen": screen.rawValue])
    }

    var body: some Commands {
        CommandMenu("Go") {
            Button("Home") { show(.home) }.keyboardShortcut("1", modifiers: .command)
            Button("Collections") { show(.packs) }.keyboardShortcut("2", modifiers: .command)
            Button("Library") { show(.library) }.keyboardShortcut("3", modifiers: .command)
            Button("Search") { show(.search) }.keyboardShortcut("f", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("Import Music…") { libraryAction(.eraImportMusic) }.keyboardShortcut("o", modifiers: .command)
            Button("New Playlist…") { libraryAction(.eraNewPlaylist) }.keyboardShortcut("n", modifiers: .command)
        }
    }

    /// Wechselt zur Bibliothek und loest die Aktion erst aus, wenn deren View sichtbar ist.
    private func libraryAction(_ name: Notification.Name) {
        show(.library)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }
}

// Menue- und Tastaturbefehle fuer Mac (Catalyst) und iPad mit Tastatur.
struct PlaybackCommands: Commands {
    let player: PlayerEngine

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Play / Pause") { player.toggle() }
                .keyboardShortcut("p", modifiers: .command)
            Button("Next") { player.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous") { player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button("Skip Forward") { player.skipForward() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Skip Back") { player.skipBackward() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
        }
    }
}

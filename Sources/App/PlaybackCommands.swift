import SwiftUI

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

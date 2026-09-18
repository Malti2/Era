import AppIntents
import Foundation

// Interactive widget buttons (iOS 17+). The intents run inside the widget
// extension, so they cannot reach the player directly: they drop a one-shot
// command into the App Group container, which PlayerEngine consumes within a
// fraction of a second while it is alive (it always is while audio plays).
// The optimistic state flip makes the widget re-render instantly; the app's
// next publish overwrites it with the true state.

struct EraTogglePlayIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Toggles playback in Era.")

    func perform() async throws -> some IntentResult {
        EraShared.writeCommand(.toggle)
        if var now = EraShared.readNowPlaying() {
            now.isPlaying.toggle()
            now.updatedAt = Date()
            EraShared.writeNowPlaying(now)
        }
        return .result()
    }
}

struct EraNextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skips to the next track in Era.")

    func perform() async throws -> some IntentResult {
        EraShared.writeCommand(.next)
        return .result()
    }
}

import Foundation
import AppIntents

// App Shortcuts (Apple-Doku: AppShortcutsProvider): fest verdrahtete
// Siri-Kurzbefehle ohne Nutzer-Setup. Steuern den lokalen Player - komplett offline.

struct EraPlayIntent: AppIntent {
    static var title: LocalizedStringResource = "Play music"
    static var description = IntentDescription("Resumes the last music played in Era.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PlayerEngine.shared.resumeOrPlay()
        return .result()
    }
}

struct EraPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause music"
    static var description = IntentDescription("Pauses playback in Era.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = PlayerEngine.shared
        if player.isPlaying { player.toggle() }
        return .result()
    }
}

struct EraNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Next track"
    static var description = IntentDescription("Skips to the next track in Era.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PlayerEngine.shared.next()
        return .result()
    }
}

struct EraPlayMixIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Daily Mix"
    static var description = IntentDescription("Plays today's mix of favorites and forgotten songs from your library.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = PlayerEngine.shared
        guard let store = player.store, let library = try? store.allSongs() else { return .result() }
        let queue = MixPlaylist.songs(.daily, in: library).compactMap(\.primaryVersion)
        if let first = queue.first { player.play(first, from: queue) }
        return .result()
    }
}

struct EraPlayBestOfIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Best Of"
    static var description = IntentDescription("Plays a mix of your 4 and 5 star songs.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = PlayerEngine.shared
        guard let store = player.store, let library = try? store.allSongs() else { return .result() }
        let queue = MixPlaylist.songs(.bestOf, in: library).compactMap(\.primaryVersion)
        if let first = queue.first { player.play(first, from: queue) }
        return .result()
    }
}

struct EraStartRadioIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Radio"
    static var description = IntentDescription("Plays songs similar to what you are listening to.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PlayerEngine.shared.startRadioFromContext()
        return .result()
    }
}

struct EraShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .grape

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EraPlayIntent(),
            phrases: [
                "Play music with \(.applicationName)",
                "Play \(.applicationName)",
                "Continue listening with \(.applicationName)"
            ],
            shortTitle: "Play",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: EraPauseIntent(),
            phrases: [
                "Pause music with \(.applicationName)",
                "Pause \(.applicationName)"
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: EraNextIntent(),
            phrases: [
                "Next track with \(.applicationName)",
                "Next in \(.applicationName)"
            ],
            shortTitle: "Next track",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: EraPlayMixIntent(),
            phrases: [
                "Play my daily mix with \(.applicationName)",
                "Play a mix in \(.applicationName)"
            ],
            shortTitle: "Daily Mix",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: EraPlayBestOfIntent(),
            phrases: [
                "Play my best songs with \(.applicationName)",
                "Play best of \(.applicationName)"
            ],
            shortTitle: "Best Of",
            systemImageName: "star.fill"
        )
        AppShortcut(
            intent: EraStartRadioIntent(),
            phrases: [
                "Start radio with \(.applicationName)",
                "Play something similar in \(.applicationName)"
            ],
            shortTitle: "Start Radio",
            systemImageName: "dot.radiowaves.left.and.right"
        )
    }
}

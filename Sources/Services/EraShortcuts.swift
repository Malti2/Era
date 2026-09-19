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
    }
}

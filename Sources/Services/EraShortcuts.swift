import Foundation
import AppIntents

// App Shortcuts (Apple-Doku: AppShortcutsProvider): fest verdrahtete
// Siri-Kurzbefehle ohne Nutzer-Setup. Steuern den lokalen Player - komplett offline.

struct EraPlayIntent: AppIntent {
    static var title: LocalizedStringResource = "Musik abspielen"
    static var description = IntentDescription("Spielt die zuletzt gehörte Musik in Era weiter.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PlayerEngine.shared.resumeOrPlay()
        return .result()
    }
}

struct EraPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Musik pausieren"
    static var description = IntentDescription("Pausiert die Wiedergabe in Era.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = PlayerEngine.shared
        if player.isPlaying { player.toggle() }
        return .result()
    }
}

struct EraNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Nächster Titel"
    static var description = IntentDescription("Springt in Era zum nächsten Titel.")
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
                "Musik abspielen mit \(.applicationName)",
                "\(.applicationName) abspielen",
                "Weiterhören mit \(.applicationName)"
            ],
            shortTitle: "Abspielen",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: EraPauseIntent(),
            phrases: [
                "Musik pausieren mit \(.applicationName)",
                "\(.applicationName) pausieren"
            ],
            shortTitle: "Pausieren",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: EraNextIntent(),
            phrases: [
                "Nächster Titel mit \(.applicationName)",
                "\(.applicationName) weiter"
            ],
            shortTitle: "Nächster Titel",
            systemImageName: "forward.fill"
        )
    }
}

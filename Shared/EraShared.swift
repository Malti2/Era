import Foundation

// Shared between the Era app and the widget extension through the App Group
// container. The app writes now-playing + recently played + artwork, widgets
// read them; widgets write one-shot playback commands, the app consumes them.
enum EraShared {
    static let groupID = "group.de.malte.era"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }
    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    struct RecentTrack: Codable, Identifiable, Hashable {
        let id: UUID
        let title: String
        let artist: String
        let artwork: String?
    }

    struct NowPlaying: Codable, Hashable {
        var trackID: UUID
        var title: String
        var artist: String
        var artwork: String?
        var isPlaying: Bool
        var position: Double
        var duration: Double
        var updatedAt: Date
    }

    enum WidgetCommand: String, Codable {
        case toggle
        case next
        case previous
    }

    struct PendingCommand: Codable {
        let command: WidgetCommand
        let at: Date
    }

    private static var recentURL: URL? {
        container?.appendingPathComponent("recent.json")
    }
    private static var nowPlayingURL: URL? {
        container?.appendingPathComponent("nowplaying.json")
    }
    private static var commandURL: URL? {
        container?.appendingPathComponent("command.json")
    }
    static var artworkDir: URL? {
        guard let dir = container?.appendingPathComponent("Artwork", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func write<T: Encodable>(_ value: T, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
    private static func read<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func writeRecent(_ tracks: [RecentTrack]) { write(tracks, to: recentURL) }
    static func readRecent() -> [RecentTrack] { read([RecentTrack].self, from: recentURL) ?? [] }

    static func writeNowPlaying(_ value: NowPlaying) { write(value, to: nowPlayingURL) }
    static func readNowPlaying() -> NowPlaying? { read(NowPlaying.self, from: nowPlayingURL) }
    static func clearNowPlaying() {
        guard let url = nowPlayingURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // One-shot command channel widget -> app. The app consumes and deletes it.
    static func writeCommand(_ command: WidgetCommand) {
        write(PendingCommand(command: command, at: Date()), to: commandURL)
    }
    static func readCommand() -> PendingCommand? { read(PendingCommand.self, from: commandURL) }
    static func clearCommand() {
        guard let url = commandURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func artworkURL(_ name: String) -> URL? {
        artworkDir?.appendingPathComponent(name)
    }

    static func copyArtwork(data: Data, name: String) {
        guard let url = artworkURL(name) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func resetShared() {
        guard let container else { return }
        for file in ["recent.json", "nowplaying.json", "command.json"] {
            try? FileManager.default.removeItem(at: container.appendingPathComponent(file))
        }
        try? FileManager.default.removeItem(at: container.appendingPathComponent("Artwork", isDirectory: true))
        defaults?.removePersistentDomain(forName: groupID)
    }
}

import Foundation

// Shared between the Era app and the widget extension through the App Group
// container. The app writes the recently played list + artwork, widgets read it.
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

    private static var recentURL: URL? {
        container?.appendingPathComponent("recent.json")
    }
    static var artworkDir: URL? {
        guard let dir = container?.appendingPathComponent("Artwork", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func writeRecent(_ tracks: [RecentTrack]) {
        guard let url = recentURL, let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func readRecent() -> [RecentTrack] {
        guard let url = recentURL, let data = try? Data(contentsOf: url),
              let tracks = try? JSONDecoder().decode([RecentTrack].self, from: data) else { return [] }
        return tracks
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
        try? FileManager.default.removeItem(at: container.appendingPathComponent("recent.json"))
        try? FileManager.default.removeItem(at: container.appendingPathComponent("Artwork", isDirectory: true))
        defaults?.removePersistentDomain(forName: groupID)
    }
}

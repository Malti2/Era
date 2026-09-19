import Foundation
import SwiftData
import Combine

// Persistenz hinter Repository-Protokollen (Spec 13.1): die App spricht nur mit
// den Protokollen, die SwiftData-Implementierung ist austauschbar (z.B. Sync spaeter).

protocol SongRepository {
    func insertSong(_ song: Song)
    func deleteSong(_ song: Song)
    func allSongs() throws -> [Song]
    func allVersions() throws -> [SongVersion]
    func version(matchingHash hash: String, duration: Double) throws -> SongVersion?
}

protocol TagRepository {
    func ensureStatusTags()
    func allTags() throws -> [Tag]
    func tag(named name: String) throws -> Tag?
    func makeTag(named name: String, scope: Tag.Scope, isStatus: Bool) -> Tag
    func deleteTag(_ tag: Tag)
}

protocol PackRepository {
    func insertPack(_ pack: Pack)
    func deletePack(_ pack: Pack)
    func allPacks() throws -> [Pack]
}

protocol PlaylistRepository {
    func insertPlaylist(_ playlist: Playlist)
    func deletePlaylist(_ playlist: Playlist)
    func allPlaylists() throws -> [Playlist]
    func appendEntry(song: Song, version: SongVersion?, to playlist: Playlist)
    func removeEntry(_ entry: PlaylistEntry, from playlist: Playlist)
}

enum Persistence {
    static let shared: ModelContainer = makeContainer()

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([Song.self, SongVersion.self, Tag.self, Pack.self, Playlist.self, PlaylistEntry.self, PlayEvent.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Bei einem Schema-Konflikt (Beta-Installationen): lokalen Store zuruecksetzen statt Absturz.
            let url = config.url
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-wal"))
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-shm"))
            return (try? ModelContainer(for: schema, configurations: [config])) ?? {
                // letzter Ausweg: In-Memory, App bleibt benutzbar
                let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try! ModelContainer(for: schema, configurations: [fallback])
            }()
        }
    }
}

@MainActor
final class EraStore: ObservableObject {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func save() { try? context.save() }
}

extension EraStore: SongRepository {
    func insertSong(_ song: Song) { context.insert(song); save() }
    func deleteSong(_ song: Song) {
        for playlist in (try? allPlaylists()) ?? [] {
            for entry in playlist.entries where entry.song?.id == song.id { context.delete(entry) }
        }
        for v in song.versions { VersionFiles.delete(version: v) }
        context.delete(song)
        save()
    }
    func allSongs() throws -> [Song] { try context.fetch(FetchDescriptor<Song>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])) }
    func allVersions() throws -> [SongVersion] { try context.fetch(FetchDescriptor<SongVersion>()) }
    func version(matchingHash hash: String, duration: Double) throws -> SongVersion? {
        // Hash ist der Primaerabgleich, Dauer das zweite Kriterium (Spec 13.3)
        try allVersions().first { $0.pcmHash == hash && abs($0.duration - duration) < 0.5 }
    }
}

extension EraStore: TagRepository {
    func ensureStatusTags() {
        let existing = (try? allTags()) ?? []
        for name in StatusTag.all where !existing.contains(where: { $0.name == name }) {
            context.insert(Tag(name: name, scope: .global, isStatus: true))
        }
        save()
    }
    func allTags() throws -> [Tag] { try context.fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)])) }
    func tag(named name: String) throws -> Tag? { try allTags().first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } }
    func makeTag(named name: String, scope: Tag.Scope = .personal, isStatus: Bool = false) -> Tag {
        if let existing = try? tag(named: name) { return existing }
        let tag = Tag(name: name, scope: scope, isStatus: isStatus)
        context.insert(tag); save()
        return tag
    }
    func deleteTag(_ tag: Tag) { context.delete(tag); save() }
}

extension EraStore {
    /// Verworfene Pack-Vorschlaege (UserDefaults, kein Schema-Eingriff noetig).
    private static let dismissedKey = "dismissedPackSuggestionNames"

    func suggestPacksFromLibrary() {
        guard let songs = try? allSongs(), !songs.isEmpty,
              let packs = try? allPacks(), let tags = try? allTags() else { return }
        var existingNames = Set(packs.map { $0.name.lowercased() })
        existingNames.formUnion(UserDefaults.standard.stringArray(forKey: EraStore.dismissedKey) ?? [])
        // Das dynamische "Favorites"-Pack existiert immer - kein doppelter Vorschlag
        let dynamicNames: Set<String> = ["favoriten", "favorite", "meistgespielt", "recently added"]
        for tag in tags {
            let count = songs.filter { $0.tags.contains { $0.id == tag.id } }.count
            guard count >= 2,
                  !existingNames.contains(tag.name.lowercased()),
                  !dynamicNames.contains(tag.name.lowercased()) else { continue }
            let pack = Pack(name: tag.name, tagIDs: tag.isStatus ? [] : [tag.id],
                            statusNames: tag.isStatus ? [tag.name] : [], confirmed: false)
            context.insert(pack)
        }
        save()
    }
}

extension EraStore: PackRepository {
    func insertPack(_ pack: Pack) { context.insert(pack); save() }
    func deletePack(_ pack: Pack) { context.delete(pack); save() }
    /// Verwirft einen Pack-Vorschlag dauerhaft - erscheint beim naechsten Start nicht erneut.
    func dismissPackSuggestion(_ pack: Pack) {
        var dismissed = UserDefaults.standard.stringArray(forKey: EraStore.dismissedKey) ?? []
        let name = pack.name.lowercased()
        if !dismissed.contains(name) {
            dismissed.append(name)
            UserDefaults.standard.set(dismissed, forKey: EraStore.dismissedKey)
        }
        context.delete(pack)
        save()
    }
    func allPacks() throws -> [Pack] { try context.fetch(FetchDescriptor<Pack>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])) }
}

extension EraStore: PlaylistRepository {
    func insertPlaylist(_ playlist: Playlist) { context.insert(playlist); save() }
    func deletePlaylist(_ playlist: Playlist) { context.delete(playlist); save() }
    func allPlaylists() throws -> [Playlist] { try context.fetch(FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])) }
    func appendEntry(song: Song, version: SongVersion?, to playlist: Playlist) {
        let entry = PlaylistEntry(position: (playlist.entries.map(\.position).max() ?? -1) + 1, song: song, versionID: version?.id)
        entry.playlist = playlist
        context.insert(entry); save()
    }
    func removeEntry(_ entry: PlaylistEntry, from playlist: Playlist) {
        playlist.entries.removeAll { $0.id == entry.id }
        context.delete(entry)
        for (index, rest) in playlist.sortedEntries.enumerated() { rest.position = index }
        save()
    }

    func resetEverything() {
        for song in (try? allSongs()) ?? [] { for version in song.versions { VersionFiles.delete(version: version) } }
        try? FileManager.default.removeItem(at: LibraryFiles.root)
        for entry in (try? context.fetch(FetchDescriptor<PlaylistEntry>())) ?? [] { context.delete(entry) }
        for playlist in (try? allPlaylists()) ?? [] { context.delete(playlist) }
        for pack in (try? allPacks()) ?? [] { context.delete(pack) }
        for song in (try? allSongs()) ?? [] { context.delete(song) }
        for tag in (try? allTags()) ?? [] { context.delete(tag) }
        for event in (try? context.fetch(FetchDescriptor<PlayEvent>())) ?? [] { context.delete(event) }
        save()
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "de.malte.era")
        SpotlightIndexer.clearAll()
    }
}

// MARK: - Dateiablage (App-Container, relativer Pfad + Hash - Spec 13.2)

enum LibraryFiles {
    static var root: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EraLibrary", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var artworkDir: URL {
        let url = root.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func url(for version: SongVersion) -> URL { root.appendingPathComponent(version.fileName) }
    static func artworkURL(_ file: String) -> URL { artworkDir.appendingPathComponent(file) }

    static func librarySizeText() -> String {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let art = (try? FileManager.default.contentsOfDirectory(at: artworkDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let total = (files + art).reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        if total == 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }
}

enum VersionFiles {
    static func delete(version: SongVersion) {
        try? FileManager.default.removeItem(at: LibraryFiles.url(for: version))
        if let art = version.artworkFile { try? FileManager.default.removeItem(at: LibraryFiles.artworkURL(art)) }
    }
}

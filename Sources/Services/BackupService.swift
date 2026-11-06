import Foundation
import SwiftData

// JSON-Backup der Bibliothek (Metadaten, keine Audiodateien): Songs, Versionen,
// Tags, Packs, Playlists, Hoerverlauf. Export ueber das native Share-Sheet,
// Import (Merge) ueber den Dokument-Picker (Einstellungen).
struct LibraryBackup: Codable {
    struct SongEntry: Codable {
        var id: UUID
        var title: String
        var artist: String
        var album: String
        var era: String
        var year: Int?
        var dateAdded: Date
        var playCount: Int
        var lastPlayedAt: Date?
        var isFavorite: Bool
        var resumePosition: Double
        var primaryVersionID: UUID?
        var tagIDs: [UUID]
    }
    struct VersionEntry: Codable {
        var id: UUID
        var songID: UUID?
        var name: String
        var fileName: String
        var pcmHash: String
        var duration: Double
        var dateAdded: Date
        var year: Int?
        var sortIndex: Int
        var titleOverride: String?
        var artistOverride: String?
        var albumOverride: String?
        var artworkFile: String?
    }
    struct TagEntry: Codable {
        var id: UUID
        var name: String
        var scopeRaw: String
        var isStatus: Bool
    }
    struct PackEntry: Codable {
        var id: UUID
        var name: String
        var tagIDs: [UUID]
        var statusNames: [String]
        var confirmed: Bool
    }
    struct PlaylistEntryItem: Codable {
        var position: Int
        var songID: UUID?
        var versionID: UUID?
    }
    struct PlaylistEntry2: Codable {
        var id: UUID
        var name: String
        var filterTagIDs: [UUID]
        var entries: [PlaylistEntryItem]
    }

    struct PlayEventEntry: Codable {
        var date: Date
        var seconds: Double
        var songID: UUID?
        var title: String
        var artist: String
    }

    static let currentFormatVersion = 2

    var app: String = "Era"
    var formatVersion: Int = LibraryBackup.currentFormatVersion
    var createdAt: Date = Date()
    var songs: [SongEntry]
    var versions: [VersionEntry]
    var tags: [TagEntry]
    var packs: [PackEntry]
    var playlists: [PlaylistEntry2]
    /// Added in format 2; older backups decode with nil.
    var playEvents: [PlayEventEntry]? = nil
}

enum BackupError: LocalizedError {
    case notABackup
    case newerFormat(Int)

    var errorDescription: String? {
        switch self {
        case .notABackup: String(localized: "This file is not an Era backup.")
        case .newerFormat: String(localized: "This backup was made by a newer version of Era.")
        }
    }
}

struct RestoreSummary: Equatable {
    var songsAdded = 0
    var versionsAdded = 0
    var songsSkippedMissingAudio = 0
    var tagsAdded = 0
    var playlistsAdded = 0
    var packsAdded = 0
    var eventsAdded = 0

    var isEmpty: Bool { songsAdded + versionsAdded + tagsAdded + playlistsAdded + packsAdded + eventsAdded == 0 }
}

enum BackupService {
    @MainActor
    static func exportURL(store: EraStore) throws -> URL {
        let backup = try makeBackup(store: store)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Era-Backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    static func makeBackup(store: EraStore) throws -> LibraryBackup {
        let songs = try store.allSongs()
        let versions = try store.allVersions()
        let tags = try store.allTags()
        let packs = try store.allPacks()
        let playlists = try store.allPlaylists()

        let events = try store.context.fetch(FetchDescriptor<PlayEvent>(sortBy: [SortDescriptor(\.date)]))

        return LibraryBackup(
            songs: songs.map { song in
                LibraryBackup.SongEntry(
                    id: song.id, title: song.title, artist: song.artist, album: song.album,
                    era: song.era, year: song.year, dateAdded: song.dateAdded,
                    playCount: song.playCount, lastPlayedAt: song.lastPlayedAt,
                    isFavorite: song.isFavorite, resumePosition: song.resumePosition,
                    primaryVersionID: song.primaryVersionID, tagIDs: song.tags.map(\.id)
                )
            },
            versions: versions.map { v in
                LibraryBackup.VersionEntry(
                    id: v.id, songID: v.song?.id, name: v.name, fileName: v.fileName,
                    pcmHash: v.pcmHash, duration: v.duration, dateAdded: v.dateAdded,
                    year: v.year, sortIndex: v.sortIndex, titleOverride: v.titleOverride,
                    artistOverride: v.artistOverride, albumOverride: v.albumOverride,
                    artworkFile: v.artworkFile
                )
            },
            tags: tags.map { LibraryBackup.TagEntry(id: $0.id, name: $0.name, scopeRaw: $0.scopeRaw, isStatus: $0.isStatus) },
            packs: packs.map { LibraryBackup.PackEntry(id: $0.id, name: $0.name, tagIDs: $0.tagIDs, statusNames: $0.statusNames, confirmed: $0.confirmed) },
            playlists: playlists.map { playlist in
                LibraryBackup.PlaylistEntry2(
                    id: playlist.id, name: playlist.name, filterTagIDs: playlist.filterTagIDs,
                    entries: playlist.sortedEntries.map {
                        LibraryBackup.PlaylistEntryItem(position: $0.position, songID: $0.song?.id, versionID: $0.versionID)
                    }
                )
            },
            playEvents: events.map {
                LibraryBackup.PlayEventEntry(date: $0.date, seconds: $0.seconds, songID: $0.songID, title: $0.title, artist: $0.artist)
            }
        )
    }

    static func decode(_ data: Data) throws -> LibraryBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: LibraryBackup
        do { backup = try decoder.decode(LibraryBackup.self, from: data) } catch { throw BackupError.notABackup }
        guard backup.app == "Era" else { throw BackupError.notABackup }
        guard backup.formatVersion <= LibraryBackup.currentFormatVersion else { throw BackupError.newerFormat(backup.formatVersion) }
        return backup
    }

    /// Merges a backup into the library without touching anything that already exists
    /// (matched by id). Because backups carry no audio, a version is only restored when
    /// its file is still on disk - e.g. after a database reset that kept EraLibrary.
    @MainActor
    @discardableResult
    static func restore(_ backup: LibraryBackup, into store: EraStore,
                        audioExists: (String) -> Bool = { FileManager.default.fileExists(atPath: LibraryFiles.root.appendingPathComponent($0).path) }) throws -> RestoreSummary {
        var summary = RestoreSummary()
        let context = store.context

        // Tags: match by id, then by name, otherwise recreate with the original id.
        var tagMap: [UUID: Tag] = [:]
        let existingTags = try store.allTags()
        for entry in backup.tags {
            if let match = existingTags.first(where: { $0.id == entry.id })
                ?? existingTags.first(where: { $0.name.localizedCaseInsensitiveCompare(entry.name) == .orderedSame }) {
                tagMap[entry.id] = match
            } else {
                let tag = Tag(name: entry.name, scope: Tag.Scope(rawValue: entry.scopeRaw) ?? .personal, isStatus: entry.isStatus)
                tag.id = entry.id
                context.insert(tag)
                tagMap[entry.id] = tag
                summary.tagsAdded += 1
            }
        }

        // Songs + versions.
        var songByID: [UUID: Song] = Dictionary(try store.allSongs().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var versionByID: [UUID: SongVersion] = Dictionary(try store.allVersions().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let knownHashes = Set(versionByID.values.map { "\($0.pcmHash)|\(Int($0.duration))" })
        let versionsBySong = Dictionary(grouping: backup.versions.filter { $0.songID != nil }, by: { $0.songID! })

        for entry in backup.songs where songByID[entry.id] == nil {
            let restorable = (versionsBySong[entry.id] ?? []).filter {
                versionByID[$0.id] == nil && audioExists($0.fileName) && !knownHashes.contains("\($0.pcmHash)|\(Int($0.duration))")
            }
            guard !restorable.isEmpty else { summary.songsSkippedMissingAudio += 1; continue }
            let song = Song(title: entry.title, artist: entry.artist, album: entry.album, era: entry.era, year: entry.year)
            song.id = entry.id
            song.dateAdded = entry.dateAdded
            song.playCount = entry.playCount
            song.lastPlayedAt = entry.lastPlayedAt
            song.isFavorite = entry.isFavorite
            song.resumePosition = entry.resumePosition
            context.insert(song)
            for v in restorable {
                let version = SongVersion(name: v.name, fileName: v.fileName, pcmHash: v.pcmHash, duration: v.duration, year: v.year)
                version.id = v.id
                version.dateAdded = v.dateAdded
                version.sortIndex = v.sortIndex
                version.titleOverride = v.titleOverride
                version.artistOverride = v.artistOverride
                version.albumOverride = v.albumOverride
                version.artworkFile = v.artworkFile
                version.song = song
                song.versions.append(version)
                versionByID[v.id] = version
                summary.versionsAdded += 1
            }
            song.primaryVersionID = song.versions.contains { $0.id == entry.primaryVersionID } ? entry.primaryVersionID : song.sortedVersions.first?.id
            for tagID in entry.tagIDs { if let tag = tagMap[tagID], !song.tags.contains(where: { $0.id == tag.id }) { song.tags.append(tag) } }
            songByID[song.id] = song
            summary.songsAdded += 1
        }

        // Packs.
        let existingPacks = try store.allPacks()
        for entry in backup.packs where !existingPacks.contains(where: { $0.id == entry.id }) {
            let ids = entry.tagIDs.map { tagMap[$0]?.id ?? $0 }
            let pack = Pack(name: entry.name, tagIDs: ids, statusNames: entry.statusNames, confirmed: entry.confirmed)
            pack.id = entry.id
            context.insert(pack)
            summary.packsAdded += 1
        }

        // Playlists: new ones are created, existing ones gain missing songs.
        var playlists = try store.allPlaylists()
        for entry in backup.playlists {
            let playlist: Playlist
            if let match = playlists.first(where: { $0.id == entry.id }) {
                playlist = match
            } else {
                playlist = Playlist(name: entry.name)
                playlist.id = entry.id
                playlist.filterTagIDs = entry.filterTagIDs.map { tagMap[$0]?.id ?? $0 }
                context.insert(playlist)
                playlists.append(playlist)
                summary.playlistsAdded += 1
            }
            for item in entry.entries.sorted(by: { $0.position < $1.position }) {
                guard let songID = item.songID, let song = songByID[songID] else { continue }
                store.appendEntry(song: song, version: item.versionID.flatMap { versionByID[$0] }, to: playlist)
            }
        }

        // Listening history: skip events that are already there.
        let existingEvents = try context.fetch(FetchDescriptor<PlayEvent>())
        var seen = Set(existingEvents.map { "\(Int($0.date.timeIntervalSince1970))|\($0.title)|\($0.artist)" })
        for e in backup.playEvents ?? [] {
            let key = "\(Int(e.date.timeIntervalSince1970))|\(e.title)|\(e.artist)"
            guard seen.insert(key).inserted else { continue }
            context.insert(PlayEvent(date: e.date, seconds: e.seconds, songID: e.songID, title: e.title, artist: e.artist))
            summary.eventsAdded += 1
        }

        store.save()
        return summary
    }
}

import Foundation
import SwiftData

// JSON-Backup der Bibliothek (Metadaten, keine Audiodateien): Songs, Versionen,
// Tags, Packs, Playlists. Export ueber das native Share-Sheet (Einstellungen).
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

    var app: String = "Era"
    var formatVersion: Int = 1
    var createdAt: Date = Date()
    var songs: [SongEntry]
    var versions: [VersionEntry]
    var tags: [TagEntry]
    var packs: [PackEntry]
    var playlists: [PlaylistEntry2]
}

enum BackupService {
    @MainActor
    static func exportURL(store: EraStore) throws -> URL {
        let songs = try store.allSongs()
        let versions = try store.allVersions()
        let tags = try store.allTags()
        let packs = try store.allPacks()
        let playlists = try store.allPlaylists()

        let backup = LibraryBackup(
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
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Era-Backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

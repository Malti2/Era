import Foundation

// JSON-Backup der Bibliothek (Metadaten, keine Audiodateien): Songs, Versionen,
// Tags, Packs, Playlists. Export ueber das native Share-Sheet (Einstellungen).
struct LibraryBackup: Codable, Equatable {
    struct SongEntry: Codable, Equatable {
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
        /// Seit Notizen/Marker: optional, damit alte Backups weiter lesbar bleiben.
        var notes: String?
    }
    struct VersionEntry: Codable, Equatable {
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
        var markersJSON: String?
    }
    struct TagEntry: Codable, Equatable {
        var id: UUID
        var name: String
        var scopeRaw: String
        var isStatus: Bool
    }
    struct PackEntry: Codable, Equatable {
        var id: UUID
        var name: String
        var tagIDs: [UUID]
        var statusNames: [String]
        var confirmed: Bool
    }
    struct PlaylistEntryItem: Codable, Equatable {
        var position: Int
        var songID: UUID?
        var versionID: UUID?
    }
    struct PlaylistEntry2: Codable, Equatable {
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


// MARK: - Lesen

enum BackupError: Error, Equatable {
    case unreadable
    case notAnEraBackup
    case newerFormat(Int)
}

extension LibraryBackup {
    static let currentFormatVersion = 1

    static func decode(from data: Data) throws -> LibraryBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: LibraryBackup
        do { backup = try decoder.decode(LibraryBackup.self, from: data) } catch { throw BackupError.unreadable }
        guard backup.app == "Era" else { throw BackupError.notAnEraBackup }
        guard backup.formatVersion <= currentFormatVersion else { throw BackupError.newerFormat(backup.formatVersion) }
        return backup
    }
}

// MARK: - Wiederherstellen (Planung)

/// Was beim Einspielen eines Backups passieren soll. Rein rechnerisch: das Backup
/// wird mit dem Ist-Zustand der Bibliothek abgeglichen, es wird nichts ueberschrieben.
struct RestorePlan: Equatable {
    struct SongPlan: Equatable {
        var song: LibraryBackup.SongEntry
        var versions: [LibraryBackup.VersionEntry]
    }

    var songs: [SongPlan] = []
    var skippedExisting = 0
    var skippedMissingAudio = 0
    /// Ids aller Songs, die nach dem Restore existieren (neue + bereits vorhandene) -
    /// Playlist-Eintraege duerfen nur darauf zeigen.
    var resolvableSongIDs: Set<UUID> = []
    var newPacks: [LibraryBackup.PackEntry] = []
    var newPlaylists: [LibraryBackup.PlaylistEntry2] = []

    var isEmpty: Bool { songs.isEmpty && newPacks.isEmpty && newPlaylists.isEmpty }
}

struct LibraryState {
    var songIDs: Set<UUID> = []
    var versionIDs: Set<UUID> = []
    var pcmHashes: Set<String> = []
    var packNames: Set<String> = []
    var playlistIDs: Set<UUID> = []
    var audioFileNames: Set<String> = []
}

enum RestorePlanner {
    static func plan(_ backup: LibraryBackup, against state: LibraryState) -> RestorePlan {
        var plan = RestorePlan()
        plan.resolvableSongIDs = state.songIDs
        let versionsBySong = Dictionary(grouping: backup.versions.filter { $0.songID != nil }, by: { $0.songID! })
        var usedHashes = state.pcmHashes
        for song in backup.songs {
            if state.songIDs.contains(song.id) { plan.skippedExisting += 1; continue }
            var keep: [LibraryBackup.VersionEntry] = []
            for version in (versionsBySong[song.id] ?? []).sorted(by: { $0.sortIndex < $1.sortIndex }) {
                guard !state.versionIDs.contains(version.id), !usedHashes.contains(version.pcmHash) else { continue }
                guard state.audioFileNames.contains(version.fileName) else { plan.skippedMissingAudio += 1; continue }
                usedHashes.insert(version.pcmHash)
                keep.append(version)
            }
            guard !keep.isEmpty else { continue }
            plan.songs.append(RestorePlan.SongPlan(song: song, versions: keep))
            plan.resolvableSongIDs.insert(song.id)
        }
        let existingPacks = state.packNames.map { $0.lowercased() }
        plan.newPacks = backup.packs.filter { !existingPacks.contains($0.name.lowercased()) }
        plan.newPlaylists = backup.playlists.filter { !state.playlistIDs.contains($0.id) }
        return plan
    }
}

struct RestoreSummary: Equatable {
    var songs = 0
    var versions = 0
    var playlists = 0
    var packs = 0
    var skippedExisting = 0
    var skippedMissingAudio = 0

    var restoredAnything: Bool { songs + playlists + packs > 0 }
}

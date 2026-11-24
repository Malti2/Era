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
        var rating: Int?
        var trackNumber: Int?
        /// Seit Disc-Nummern: optional, damit alte Backups weiter lesbar bleiben.
        var discNumber: Int? = nil
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
        // Regel v2 - optional, damit aeltere Backups weiter lesbar bleiben.
        var excludedTagIDs: [UUID]? = nil
        var excludedStatusNames: [String]? = nil
        var matchAny: Bool? = nil
        var searchQuery: String? = nil
        // Regel-Gruppen (JSON wie im Pack) - optional, aeltere Backups haben keine.
        var groupsJSON: String? = nil
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

    /// Hoerverlauf (Stats, Verlauf, Rueckblick). Aeltere Backups haben ihn nicht.
    struct PlayEventEntry: Codable, Equatable {
        var id: UUID
        var date: Date
        var seconds: Double
        var songID: UUID?
        var title: String
        var artist: String
    }

    /// Einstellungen und Suchen (Wiedergabe, Hoerziel, gespeicherte Suchen,
    /// ignorierte Dubletten-Hinweise). Alles optional: alte Backups haben den Block
    /// nicht, und beim Restore gilt nur, was gesetzt ist - der Rest bleibt, wie er ist.
    struct SettingsEntry: Codable, Equatable {
        var defaultRate: Double?
        var skipInterval: Int?
        var pauseOnRouteChange: Bool?
        var resumeAfterInterruption: Bool?
        var hapticsEnabled: Bool?
        var spotlightEnabled: Bool?
        var crackleEnabled: Bool?
        var crackleVolume: Double?
        var transitionStyle: String?
        var crossfadeSeconds: Int?
        var autoplay: Bool?
        var weeklyGoalMinutes: Int?
        var savedSearches: [SavedSearch]?
        var recentSearches: [String]?
        var ignoredSimilar: [String]?
    }

    var app: String = "Era"
    var formatVersion: Int = 1
    var createdAt: Date = Date()
    var songs: [SongEntry]
    var versions: [VersionEntry]
    var tags: [TagEntry]
    var packs: [PackEntry]
    var playlists: [PlaylistEntry2]
    var playEvents: [PlayEventEntry]?
    /// Einstellungen, s. `SettingsEntry`. Fehlt in Backups vor diesem Stand.
    var settings: SettingsEntry? = nil
    /// FNV-1a-Pruefsumme ueber den Rest des Backups (ohne dieses Feld). Fehlt in
    /// alten Backups - die bleiben lesbar, werden nur nicht geprueft.
    var checksum: String? = nil
}


// MARK: - Lesen

enum BackupError: Error, Equatable {
    case unreadable
    case notAnEraBackup
    case newerFormat(Int)
    /// Die Pruefsumme stimmt nicht: die Datei wurde veraendert oder ist beschaedigt.
    case checksumMismatch
    /// Inhaltlich unsinnige Werte (doppelte IDs, negative Dauer, Rating ausserhalb 0...5).
    case invalidContent(String)
}

extension LibraryBackup {
    static let currentFormatVersion = 1

    /// FNV-1a-64 ueber die kanonische JSON-Kodierung (sortierte Keys, ISO-8601),
    /// ohne das Checksummen-Feld selbst. Kein CryptoKit noetig (Linux-faehig).
    static func checksum(of backup: LibraryBackup) -> String {
        var copy = backup
        copy.checksum = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(copy) else { return "" }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let raw = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - raw.count)) + raw
    }

    /// Erste inhaltliche Auffaelligkeit, oder nil wenn alles plausibel ist.
    /// Faengt beschaedigte oder von Hand verfaelschte Backups ab, bevor der
    /// Restore sie einspielt (leere Listen und fehlende optionale Felder sind ok).
    static func validate(_ backup: LibraryBackup) -> String? {
        func duplicates<T: Hashable>(_ values: [T]) -> Bool { Set(values).count != values.count }
        if duplicates(backup.songs.map(\.id)) { return "duplicate song id" }
        if duplicates(backup.versions.map(\.id)) { return "duplicate version id" }
        if duplicates(backup.tags.map(\.id)) { return "duplicate tag id" }
        if duplicates(backup.packs.map(\.id)) { return "duplicate collection id" }
        if duplicates(backup.playlists.map(\.id)) { return "duplicate playlist id" }
        // Doppelte Play-Events sind ok: der Restore-Planer deduped sie (siehe Test).
        for song in backup.songs {
            if song.playCount < 0 { return "negative play count" }
            if song.resumePosition < 0 { return "negative resume position" }
            if let rating = song.rating, rating < 0 || rating > 5 { return "rating outside 0...5" }
            if let track = song.trackNumber, track < 0 { return "negative track number" }
            if let disc = song.discNumber, disc < 0 { return "negative disc number" }
        }
        for version in backup.versions {
            if version.duration < 0 { return "negative duration" }
            if version.sortIndex < 0 { return "negative sort index" }
        }
        for playlist in backup.playlists {
            if playlist.entries.contains(where: { $0.position < 0 }) { return "negative playlist position" }
        }
        if let events = backup.playEvents, events.contains(where: { $0.seconds < 0 }) { return "negative play time" }
        if let settings = backup.settings {
            if let rate = settings.defaultRate, rate <= 0 { return "invalid default rate" }
            if let skip = settings.skipInterval, skip <= 0 { return "invalid skip interval" }
            if let goal = settings.weeklyGoalMinutes, goal < 0 { return "negative weekly goal" }
            if let crossfade = settings.crossfadeSeconds, crossfade < 0 { return "negative crossfade" }
            if let volume = settings.crackleVolume, volume < 0 || volume > 1 { return "crackle volume outside 0...1" }
        }
        return nil
    }

    static func decode(from data: Data) throws -> LibraryBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: LibraryBackup
        do { backup = try decoder.decode(LibraryBackup.self, from: data) } catch { throw BackupError.unreadable }
        guard backup.app == "Era" else { throw BackupError.notAnEraBackup }
        guard backup.formatVersion <= currentFormatVersion else { throw BackupError.newerFormat(backup.formatVersion) }
        if let expected = backup.checksum, expected != checksum(of: backup) { throw BackupError.checksumMismatch }
        if let problem = validate(backup) { throw BackupError.invalidContent(problem) }
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
    var newPlayEvents: [LibraryBackup.PlayEventEntry] = []

    var isEmpty: Bool { songs.isEmpty && newPacks.isEmpty && newPlaylists.isEmpty && newPlayEvents.isEmpty }
}

struct LibraryState {
    var songIDs: Set<UUID> = []
    var versionIDs: Set<UUID> = []
    var pcmHashes: Set<String> = []
    var packNames: Set<String> = []
    var playlistIDs: Set<UUID> = []
    var audioFileNames: Set<String> = []
    var playEventIDs: Set<UUID> = []
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
        var seenEvents = state.playEventIDs
        plan.newPlayEvents = (backup.playEvents ?? []).filter { seenEvents.insert($0.id).inserted }
        return plan
    }
}

struct RestoreSummary: Equatable {
    var songs = 0
    var versions = 0
    var playlists = 0
    var packs = 0
    var playEvents = 0
    /// Einstellungen aus dem Backup wurden uebernommen.
    var settingsRestored = false
    var skippedExisting = 0
    var skippedMissingAudio = 0

    var restoredAnything: Bool { songs + playlists + packs + playEvents > 0 || settingsRestored }
}

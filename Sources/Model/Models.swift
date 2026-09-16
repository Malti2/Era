import Foundation
import SwiftData

// MARK: - Song (Identitaet eines Tracks)

@Model
final class Song {
    var id: UUID = UUID()
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var era: String = ""
    var year: Int?
    var dateAdded: Date = Date()
    var playCount: Int = 0
    var lastPlayedAt: Date?
    var isFavorite: Bool = false
    var resumePosition: Double = 0
    var primaryVersionID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \SongVersion.song)
    var versions: [SongVersion] = []

    @Relationship(inverse: \Tag.songs)
    var tags: [Tag] = []

    init(title: String, artist: String = "", album: String = "", era: String = "", year: Int? = nil) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.album = album
        self.era = era
        self.year = year
        self.dateAdded = Date()
    }

    var sortedVersions: [SongVersion] {
        versions.sorted { lhs, rhs in
            let ly = lhs.year ?? Int.max, ry = rhs.year ?? Int.max
            if ly != ry { return ly < ry }
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.dateAdded < rhs.dateAdded
        }
    }

    var primaryVersion: SongVersion? {
        if let pid = primaryVersionID, let match = versions.first(where: { $0.id == pid }) { return match }
        return sortedVersions.first
    }

    var displayArtist: String { artist.isEmpty ? String(localized: "Unbekannter Künstler") : artist }
    var statusTags: [Tag] { tags.filter { $0.isStatus }.sorted { $0.name < $1.name } }
    var personalTags: [Tag] { tags.filter { !$0.isStatus }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var duration: Double { primaryVersion?.duration ?? 0 }
    var durationText: String { TimeFormatting.mmss(duration) }
}

// MARK: - SongVersion (Variante am Song)

@Model
final class SongVersion {
    var id: UUID = UUID()
    var name: String = ""
    var fileName: String = ""
    var pcmHash: String = ""
    var duration: Double = 0
    var dateAdded: Date = Date()
    var year: Int?
    var sortIndex: Int = 0
    var titleOverride: String?
    var artistOverride: String?
    var albumOverride: String?
    var artworkFile: String?
    var song: Song?

    init(name: String, fileName: String, pcmHash: String, duration: Double, year: Int? = nil) {
        self.id = UUID()
        self.name = name
        self.fileName = fileName
        self.pcmHash = pcmHash
        self.duration = duration
        self.dateAdded = Date()
        self.year = year
    }

    var displayTitle: String {
        if let t = titleOverride, !t.isEmpty { return t }
        return song?.title ?? ""
    }
    var displayArtist: String {
        if let a = artistOverride, !a.isEmpty { return a }
        return song?.displayArtist ?? ""
    }
    var displayAlbum: String {
        if let a = albumOverride, !a.isEmpty { return a }
        return song?.album ?? ""
    }
    var durationText: String { TimeFormatting.mmss(duration) }
}

// MARK: - Tag (flexibel, kombinierbar; Status = reservierte Tags)

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var scopeRaw: String = "personal"
    var isStatus: Bool = false
    var songs: [Song] = []

    enum Scope: String, Codable { case global, personal }
    var scope: Scope {
        get { Scope(rawValue: scopeRaw) ?? .personal }
        set { scopeRaw = newValue.rawValue }
    }

    init(name: String, scope: Scope = .personal, isStatus: Bool = false) {
        self.id = UUID()
        self.name = name
        self.scopeRaw = scope.rawValue
        self.isStatus = isStatus
    }
}

// Reservierte Status-Werte (Spec 3.1)
enum StatusTag {
    static let all = ["Released", "Unreleased", "Leak", "Demo", "Snippet", "Live", "Remix", "Alternate", "Unknown"]
}

// Versions-Presets als Chips (Spec 4)
enum VersionPreset {
    static let all = ["OG", "V2", "Demo", "Remaster", "Live", "Snippet", "Released"]
}

// MARK: - Pack (gespeicherte Query ueber Tags/Status, keine Songliste)

@Model
final class Pack {
    var id: UUID = UUID()
    var name: String = ""
    var tagIDs: [UUID] = []
    var statusNames: [String] = []
    var confirmed: Bool = false
    var dateAdded: Date = Date()

    init(name: String, tagIDs: [UUID] = [], statusNames: [String] = [], confirmed: Bool = false) {
        self.id = UUID()
        self.name = name
        self.tagIDs = tagIDs
        self.statusNames = statusNames
        self.confirmed = confirmed
        self.dateAdded = Date()
    }
}

// MARK: - Playlist (Eintraege zeigen auf Song+Version)

@Model
final class Playlist {
    var id: UUID = UUID()
    var name: String = ""
    var dateAdded: Date = Date()
    var filterTagIDs: [UUID] = []

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    var entries: [PlaylistEntry] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.dateAdded = Date()
    }

    var sortedEntries: [PlaylistEntry] { entries.sorted { $0.position < $1.position } }
}

@Model
final class PlaylistEntry {
    var id: UUID = UUID()
    var position: Int = 0
    var dateAdded: Date = Date()
    var versionID: UUID?
    var song: Song?
    var playlist: Playlist?

    init(position: Int, song: Song, versionID: UUID?) {
        self.id = UUID()
        self.position = position
        self.song = song
        self.versionID = versionID
        self.dateAdded = Date()
    }

    // Fallback: referenzierte Version weg -> primaere Version (Spec 5)
    var resolvedVersion: SongVersion? {
        if let vid = versionID, let v = song?.versions.first(where: { $0.id == vid }) { return v }
        return song?.primaryVersion
    }
}

// MARK: - Hilfe

enum TimeFormatting {
    static func mmss(_ value: Double) -> String {
        let total = max(0, Int(value))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    static func long(_ value: Double) -> String {
        let h = Int(value) / 3600, m = (Int(value) % 3600) / 60
        return h > 0 ? "\(h) Std. \(m) Min." : "\(m) Min."
    }
}

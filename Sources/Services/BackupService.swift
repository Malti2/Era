import Foundation
import SwiftData

enum BackupService {
    @MainActor
    static func exportURL(store: EraStore) throws -> URL {
        let songs = try store.allSongs()
        let versions = try store.allVersions()
        let tags = try store.allTags()
        let packs = try store.allPacks()
        let playlists = try store.allPlaylists()
        let context = store.context

        let backup = LibraryBackup(
            songs: songs.map { song in
                LibraryBackup.SongEntry(
                    id: song.id, title: song.title, artist: song.artist, album: song.album,
                    era: song.era, year: song.year, dateAdded: song.dateAdded,
                    playCount: song.playCount, lastPlayedAt: song.lastPlayedAt,
                    isFavorite: song.isFavorite, resumePosition: song.resumePosition,
                    primaryVersionID: song.primaryVersionID, tagIDs: song.tags.map(\.id),
                    notes: song.notes.isEmpty ? nil : song.notes,
                    rating: song.rating == 0 ? nil : song.rating,
                    trackNumber: song.trackNumber == 0 ? nil : song.trackNumber
                )
            },
            versions: versions.map { v in
                LibraryBackup.VersionEntry(
                    id: v.id, songID: v.song?.id, name: v.name, fileName: v.fileName,
                    pcmHash: v.pcmHash, duration: v.duration, dateAdded: v.dateAdded,
                    year: v.year, sortIndex: v.sortIndex, titleOverride: v.titleOverride,
                    artistOverride: v.artistOverride, albumOverride: v.albumOverride,
                    artworkFile: v.artworkFile,
                    markersJSON: v.markersJSON.isEmpty ? nil : v.markersJSON
                )
            },
            tags: tags.map { LibraryBackup.TagEntry(id: $0.id, name: $0.name, scopeRaw: $0.scopeRaw, isStatus: $0.isStatus) },
            packs: packs.map { LibraryBackup.PackEntry(id: $0.id, name: $0.name, tagIDs: $0.tagIDs, statusNames: $0.statusNames, confirmed: $0.confirmed,
                                                       excludedTagIDs: $0.excludedTagIDs, excludedStatusNames: $0.excludedStatusNames, matchAny: $0.matchAny,
                                                       searchQuery: $0.searchQuery.isEmpty ? nil : $0.searchQuery) },
            playlists: playlists.map { playlist in
                LibraryBackup.PlaylistEntry2(
                    id: playlist.id, name: playlist.name, filterTagIDs: playlist.filterTagIDs,
                    entries: playlist.sortedEntries.map {
                        LibraryBackup.PlaylistEntryItem(position: $0.position, songID: $0.song?.id, versionID: $0.versionID)
                    }
                )
            },
            playEvents: try context.fetch(FetchDescriptor<PlayEvent>(sortBy: [SortDescriptor(\.date)])).map {
                LibraryBackup.PlayEventEntry(id: $0.id, date: $0.date, seconds: $0.seconds, songID: $0.songID, title: $0.title, artist: $0.artist)
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

// CSV-Export der Bibliothek (eine Zeile pro Song) fuer Tabellenkalkulationen.
enum CSVExport {
    static let header = ["Title", "Artist", "Album", "Era", "Year", "Duration", "Versions", "Status", "Tags", "Plays", "Rating", "Favorite", "Date Added", "Notes", "Markers", "Track"]

    /// RFC 4180: Felder mit Komma, Anfuehrungszeichen oder Zeilenumbruch werden gequotet.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// "OG 0:42 Hook; V2 1:05" - Marker aller Versionen in einer Zelle.
    static func markerSummary(of song: Song) -> String {
        song.sortedVersions.flatMap { version in
            version.markers.map { marker in
                [version.name, VersionMarkers.timeText(marker.time), marker.label].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }.joined(separator: "; ")
    }

    static func csv(songs: [Song]) -> String {
        let dateFormatter = ISO8601DateFormatter()
        var lines = [header.map(escape).joined(separator: ",")]
        for song in songs {
            let fields = [
                song.title, song.artist, song.album, song.era,
                song.year.map(String.init) ?? "",
                song.durationText,
                String(song.versions.count),
                song.statusTags.map(\.name).joined(separator: "; "),
                song.personalTags.map(\.name).joined(separator: "; "),
                String(song.playCount),
                song.rating > 0 ? String(song.rating) : "",
                song.isFavorite ? "yes" : "no",
                dateFormatter.string(from: song.dateAdded),
                song.notes,
                markerSummary(of: song),
                song.trackNumber > 0 ? String(song.trackNumber) : ""
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    @MainActor
    static func exportURL(store: EraStore) throws -> URL {
        // BOM, damit Excel UTF-8 (Umlaute) korrekt erkennt.
        let data = Data("\u{FEFF}".utf8) + Data(csv(songs: try store.allSongs()).utf8)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Era-Library-\(stamp).csv")
        try data.write(to: url, options: .atomic)
        return url
    }
}

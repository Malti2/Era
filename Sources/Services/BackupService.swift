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
                    trackNumber: song.trackNumber == 0 ? nil : song.trackNumber,
                    discNumber: song.discNumber == 0 ? nil : song.discNumber
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
                                                       searchQuery: $0.searchQuery.isEmpty ? nil : $0.searchQuery,
                                                       groupsJSON: $0.groupsJSON.isEmpty ? nil : $0.groupsJSON) },
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
            },
            settings: currentSettings()
        )
        var stamped = backup
        stamped.checksum = LibraryBackup.checksum(of: backup)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(stamped)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Era-Backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Einstellungen im Backup

    /// Nur gesetzte Werte landen im Backup (nil = Standard, bleibt beim Restore unberuehrt).
    /// Ansichts-Zustand (Tab, Sortierung, Filter) und Geraete-Kram (Onboarding, Snoozes)
    /// gehoeren nicht hierher - das Backup soll die Bibliothek retten, kein Geraet klonen.
    static func currentSettings() -> LibraryBackup.SettingsEntry {
        let defaults = UserDefaults.standard
        func bool(_ key: String) -> Bool? { defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key) }
        func int(_ key: String) -> Int? { let v = defaults.integer(forKey: key); return v == 0 ? nil : v }
        func double(_ key: String) -> Double? { let v = defaults.double(forKey: key); return v == 0 ? nil : v }
        let saved = SavedSearches.decode(defaults.data(forKey: AppSettings.savedSearchesKey))
        let recents = defaults.stringArray(forKey: AppSettings.recentSearchesKey) ?? []
        let ignored = defaults.string(forKey: AppSettings.ignoredSimilarKey)?
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty } ?? []
        return LibraryBackup.SettingsEntry(
            defaultRate: double(AppSettings.defaultRateKey),
            skipInterval: int(AppSettings.skipIntervalKey),
            pauseOnRouteChange: bool(AppSettings.pauseOnRouteChangeKey),
            resumeAfterInterruption: bool(AppSettings.resumeAfterInterruptionKey),
            hapticsEnabled: bool(AppSettings.hapticsEnabledKey),
            spotlightEnabled: bool(AppSettings.spotlightEnabledKey),
            crackleEnabled: bool(AppSettings.crackleEnabledKey),
            crackleVolume: double(AppSettings.crackleVolumeKey),
            transitionStyle: defaults.string(forKey: AppSettings.transitionStyleKey),
            crossfadeSeconds: int(AppSettings.crossfadeSecondsKey),
            autoplay: bool(AppSettings.autoplayKey),
            weeklyGoalMinutes: int(AppSettings.weeklyGoalMinutesKey),
            savedSearches: saved.isEmpty ? nil : saved,
            recentSearches: recents.isEmpty ? nil : recents,
            ignoredSimilar: ignored.isEmpty ? nil : ignored
        )
    }

    /// Schreibt die Einstellungen eines Backups in die UserDefaults. Gibt true zurueck,
    /// wenn mindestens ein Wert uebernommen wurde (@AppStorage-Views lesen sie live).
    @discardableResult
    static func applySettings(_ settings: LibraryBackup.SettingsEntry) -> Bool {
        let defaults = UserDefaults.standard
        var applied = false
        func set<T>(_ value: T?, forKey key: String) {
            guard let value else { return }
            defaults.set(value, forKey: key)
            applied = true
        }
        set(settings.defaultRate, forKey: AppSettings.defaultRateKey)
        set(settings.skipInterval, forKey: AppSettings.skipIntervalKey)
        set(settings.pauseOnRouteChange, forKey: AppSettings.pauseOnRouteChangeKey)
        set(settings.resumeAfterInterruption, forKey: AppSettings.resumeAfterInterruptionKey)
        set(settings.hapticsEnabled, forKey: AppSettings.hapticsEnabledKey)
        set(settings.spotlightEnabled, forKey: AppSettings.spotlightEnabledKey)
        set(settings.crackleEnabled, forKey: AppSettings.crackleEnabledKey)
        set(settings.crackleVolume, forKey: AppSettings.crackleVolumeKey)
        set(settings.transitionStyle, forKey: AppSettings.transitionStyleKey)
        set(settings.crossfadeSeconds, forKey: AppSettings.crossfadeSecondsKey)
        set(settings.autoplay, forKey: AppSettings.autoplayKey)
        set(settings.weeklyGoalMinutes, forKey: AppSettings.weeklyGoalMinutesKey)
        if let saved = settings.savedSearches, let data = SavedSearches.encode(saved) {
            defaults.set(data, forKey: AppSettings.savedSearchesKey)
            applied = true
        }
        set(settings.recentSearches, forKey: AppSettings.recentSearchesKey)
        if let ignored = settings.ignoredSimilar {
            defaults.set(ignored.joined(separator: "\n"), forKey: AppSettings.ignoredSimilarKey)
            applied = true
        }
        return applied
    }
}

// CSV-Export der Bibliothek (eine Zeile pro Song) fuer Tabellenkalkulationen.
enum CSVExport {
    static let header = ["Title", "Artist", "Album", "Era", "Year", "Duration", "Versions", "Status", "Tags", "Plays", "Rating", "Favorite", "Date Added", "Notes", "Markers", "Track", "Disc"]

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
            var fields: [String] = [song.title, song.artist, song.album, song.era]
            fields.append(song.year.map(String.init) ?? "")
            fields.append(song.durationText)
            fields.append(String(song.versions.count))
            fields.append(song.statusTags.map(\.name).joined(separator: "; "))
            fields.append(song.personalTags.map(\.name).joined(separator: "; "))
            fields.append(String(song.playCount))
            fields.append(song.rating > 0 ? String(song.rating) : "")
            fields.append(song.isFavorite ? "yes" : "no")
            fields.append(dateFormatter.string(from: song.dateAdded))
            fields.append(song.notes)
            fields.append(markerSummary(of: song))
            fields.append(song.trackNumber > 0 ? String(song.trackNumber) : "")
            fields.append(song.discNumber > 0 ? String(song.discNumber) : "")
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

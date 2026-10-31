import Foundation
import SwiftData

// Wiederherstellen aus einem JSON-Backup und Reparatur-Aktionen des Bibliotheks-Checks.
// Die Entscheidungen treffen RestorePlanner / LibraryHealth (reine Logik), hier wird nur
// gegen SwiftData und das Dateisystem ausgefuehrt.

extension LibraryFiles {
    static func snapshot() -> LibraryFilesSnapshot {
        func sizes(in directory: URL) -> [String: Int] {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])) ?? []
            var result: [String: Int] = [:]
            for url in urls {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                guard values?.isDirectory != true else { continue }
                result[url.lastPathComponent] = values?.fileSize ?? 0
            }
            return result
        }
        return LibraryFilesSnapshot(audio: sizes(in: root), artwork: sizes(in: artworkDir))
    }
}

extension EraStore {
    func currentLibraryState() -> LibraryState {
        let songs = (try? allSongs()) ?? []
        return LibraryState(
            songIDs: Set(songs.map(\.id)),
            versionIDs: Set(songs.flatMap { $0.versions.map(\.id) }),
            pcmHashes: Set(songs.flatMap { $0.versions.map(\.pcmHash) }),
            packNames: Set(((try? allPacks()) ?? []).map(\.name)),
            playlistIDs: Set(((try? allPlaylists()) ?? []).map(\.id)),
            audioFileNames: Set(LibraryFiles.snapshot().audio.keys)
        )
    }

    // MARK: Health

    func healthReport() -> LibraryHealthReport {
        let songs = ((try? allSongs()) ?? []).map { song in
            HealthSong(id: song.id, title: song.title, artist: song.artist, versions: song.versions.map {
                HealthVersion(id: $0.id, name: $0.name, fileName: $0.fileName, artworkFile: $0.artworkFile)
            })
        }
        return LibraryHealth.analyze(songs: songs, files: LibraryFiles.snapshot())
    }

    /// Removes versions whose audio file is gone; songs left without a version go too.
    /// Returns the number of removed versions.
    @discardableResult
    func removeMissingAudio(_ missing: [LibraryHealthReport.MissingAudio]) -> Int {
        let ids = Set(missing.map(\.versionID))
        var removed = 0
        for song in (try? allSongs()) ?? [] {
            let doomed = song.versions.filter { ids.contains($0.id) }
            guard !doomed.isEmpty else { continue }
            for version in doomed {
                VersionFiles.delete(version: version)
                song.versions.removeAll { $0.id == version.id }
                for playlist in (try? allPlaylists()) ?? [] {
                    for entry in playlist.entries where entry.versionID == version.id { entry.versionID = nil }
                }
                context.delete(version)
                removed += 1
            }
            if song.versions.isEmpty {
                deleteSong(song)
            } else if let primary = song.primaryVersionID, ids.contains(primary) {
                song.primaryVersionID = song.sortedVersions.first?.id
            }
        }
        save()
        return removed
    }

    func removeEmptySongs() {
        for song in (try? allSongs()) ?? [] where song.versions.isEmpty { deleteSong(song) }
    }

    func clearBrokenArtwork(versionIDs: [UUID]) {
        let ids = Set(versionIDs)
        for version in (try? allVersions()) ?? [] where ids.contains(version.id) { version.artworkFile = nil }
        save()
    }

    /// Deletes stray files nobody references. Only file names from a fresh report are accepted.
    func deleteOrphans(audio: [String], artwork: [String]) {
        for name in audio where LibraryHealth.isManagedAudioFile(name) {
            try? FileManager.default.removeItem(at: LibraryFiles.root.appendingPathComponent(name))
        }
        for name in artwork where !name.contains("/") && !name.hasPrefix(".") {
            try? FileManager.default.removeItem(at: LibraryFiles.artworkURL(name))
        }
    }

    /// Merges every song of a duplicate group into the oldest one.
    func mergeDuplicates(songIDs: [UUID]) {
        let songs = ((try? allSongs()) ?? []).filter { songIDs.contains($0.id) }.sorted { $0.dateAdded < $1.dateAdded }
        guard let target = songs.first else { return }
        for source in songs.dropFirst() { mergeSongAsVersions(source, into: target) }
    }
}

extension BackupService {
    /// Merges a JSON backup into the current library. Nothing existing is overwritten;
    /// songs only come back when their audio file is still in the app container.
    @MainActor
    @discardableResult
    static func restore(from data: Data, into store: EraStore) throws -> RestoreSummary {
        let backup = try LibraryBackup.decode(from: data)
        let plan = RestorePlanner.plan(backup, against: store.currentLibraryState())
        var summary = RestoreSummary(skippedExisting: plan.skippedExisting, skippedMissingAudio: plan.skippedMissingAudio)
        let context = store.context

        // Tags: same id or same name reuse the local tag, otherwise recreate lazily.
        var localTags = try store.allTags()
        var tagMap: [UUID: Tag] = [:]
        func localTag(_ id: UUID) -> Tag? {
            if let cached = tagMap[id] { return cached }
            guard let entry = backup.tags.first(where: { $0.id == id }) else { return nil }
            let match = localTags.first { $0.id == entry.id }
                ?? localTags.first { $0.name.localizedCaseInsensitiveCompare(entry.name) == .orderedSame }
            let tag = match ?? {
                let created = Tag(name: entry.name, scope: Tag.Scope(rawValue: entry.scopeRaw) ?? .personal, isStatus: entry.isStatus)
                created.id = entry.id
                context.insert(created)
                localTags.append(created)
                return created
            }()
            tagMap[id] = tag
            return tag
        }

        for item in plan.songs {
            let entry = item.song
            let song = Song(title: entry.title, artist: entry.artist, album: entry.album, era: entry.era, year: entry.year)
            song.id = entry.id
            song.dateAdded = entry.dateAdded
            song.playCount = entry.playCount
            song.lastPlayedAt = entry.lastPlayedAt
            song.isFavorite = entry.isFavorite
            song.resumePosition = entry.resumePosition
            song.notes = entry.notes ?? ""
            for tagID in entry.tagIDs {
                if let tag = localTag(tagID), !song.tags.contains(where: { $0.id == tag.id }) { song.tags.append(tag) }
            }
            for v in item.versions {
                let version = SongVersion(name: v.name, fileName: v.fileName, pcmHash: v.pcmHash, duration: v.duration, year: v.year)
                version.id = v.id
                version.dateAdded = v.dateAdded
                version.sortIndex = v.sortIndex
                version.titleOverride = v.titleOverride
                version.artistOverride = v.artistOverride
                version.albumOverride = v.albumOverride
                version.markersJSON = v.markersJSON ?? ""
                if let art = v.artworkFile, FileManager.default.fileExists(atPath: LibraryFiles.artworkURL(art).path) {
                    version.artworkFile = art
                }
                version.song = song
                song.versions.append(version)
                summary.versions += 1
            }
            song.primaryVersionID = item.versions.contains { $0.id == entry.primaryVersionID } ? entry.primaryVersionID : item.versions.first?.id
            context.insert(song)
            summary.songs += 1
        }
        store.save()

        for entry in plan.newPacks {
            let tagIDs = entry.tagIDs.compactMap { localTag($0)?.id }
            let pack = Pack(name: entry.name, tagIDs: tagIDs, statusNames: entry.statusNames, confirmed: entry.confirmed)
            context.insert(pack)
            summary.packs += 1
        }

        let songsByID = Dictionary(((try? store.allSongs()) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in plan.newPlaylists {
            let playlist = Playlist(name: entry.name)
            playlist.id = entry.id
            playlist.filterTagIDs = entry.filterTagIDs.compactMap { localTag($0)?.id }
            context.insert(playlist)
            var position = 0
            for item in entry.entries.sorted(by: { $0.position < $1.position }) {
                guard let songID = item.songID, plan.resolvableSongIDs.contains(songID), let song = songsByID[songID],
                      !playlist.entries.contains(where: { $0.song?.id == songID }) else { continue }
                let versionID = item.versionID.flatMap { id in song.versions.contains { $0.id == id } ? id : nil }
                let playlistEntry = PlaylistEntry(position: position, song: song, versionID: versionID)
                playlistEntry.playlist = playlist
                context.insert(playlistEntry)
                position += 1
            }
            summary.playlists += 1
        }
        store.save()
        if summary.songs > 0 { SpotlightIndexer.reindex(songs: (try? store.allSongs()) ?? []) }
        return summary
    }
}

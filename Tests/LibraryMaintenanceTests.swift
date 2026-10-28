import XCTest
import SwiftData
@testable import Era

@MainActor
final class LibraryMaintenanceTests: XCTestCase {
    private var store: EraStore!
    private var createdFiles: [URL] = []

    override func setUp() async throws {
        store = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
    }

    override func tearDown() async throws {
        for url in createdFiles { try? FileManager.default.removeItem(at: url) }
        createdFiles = []
    }

    @discardableResult
    private func writeAudio(_ name: String) -> URL {
        let url = LibraryFiles.root.appendingPathComponent(name)
        try? Data("audio".utf8).write(to: url)
        createdFiles.append(url)
        return url
    }

    private func makeSong(_ title: String, withFile: Bool = true) -> Song {
        let song = Song(title: title, artist: "Tester")
        let fileName = "test-\(UUID().uuidString).m4a"
        if withFile { writeAudio(fileName) }
        let version = SongVersion(name: "OG", fileName: fileName, pcmHash: UUID().uuidString, duration: 100)
        version.song = song
        song.versions.append(version)
        song.primaryVersionID = version.id
        store.insertSong(song)
        return song
    }

    /// Simulates a reset database: rows are gone, audio files stay.
    private func dropRowsKeepingFiles() throws {
        for playlist in try store.allPlaylists() { store.context.delete(playlist) }
        for song in try store.allSongs() { store.context.delete(song) }
        for tag in try store.allTags() { store.context.delete(tag) }
        store.save()
    }

    func testRestoreBringsBackSongsTagsAndPlaylistsAfterDatabaseReset() throws {
        let song = makeSong("Keep Me")
        song.isFavorite = true
        song.playCount = 7
        song.tags.append(store.makeTag(named: "synth"))
        let playlist = try XCTUnwrap(store.createPlaylist(named: "Mix", songs: [song]))
        let backupURL = try BackupService.exportURL(store: store)
        defer { try? FileManager.default.removeItem(at: backupURL) }
        let songID = song.id, playlistID = playlist.id
        let fileName = try XCTUnwrap(song.versions.first?.fileName)
        try dropRowsKeepingFiles()
        XCTAssertTrue(try store.allSongs().isEmpty)

        let summary = try BackupService.restore(from: Data(contentsOf: backupURL), into: store)

        XCTAssertEqual(summary.songs, 1)
        XCTAssertEqual(summary.playlists, 1)
        let restored = try XCTUnwrap(try store.allSongs().first)
        XCTAssertEqual(restored.id, songID)
        XCTAssertTrue(restored.isFavorite)
        XCTAssertEqual(restored.playCount, 7)
        XCTAssertEqual(restored.personalTags.map(\.name), ["synth"])
        XCTAssertEqual(restored.primaryVersion?.fileName, fileName)
        let list = try XCTUnwrap(try store.allPlaylists().first)
        XCTAssertEqual(list.id, playlistID)
        XCTAssertEqual(list.sortedEntries.compactMap { $0.song?.id }, [songID])
    }

    func testRestoreIsIdempotentAndSkipsMissingAudio() throws {
        let present = makeSong("Present")
        let gone = makeSong("Gone")
        let backupURL = try BackupService.exportURL(store: store)
        defer { try? FileManager.default.removeItem(at: backupURL) }
        try FileManager.default.removeItem(at: LibraryFiles.url(for: try XCTUnwrap(gone.primaryVersion)))
        try dropRowsKeepingFiles()
        let data = try Data(contentsOf: backupURL)

        let first = try BackupService.restore(from: data, into: store)
        XCTAssertEqual(first.songs, 1)
        XCTAssertEqual(first.skippedMissingAudio, 1)
        XCTAssertEqual(try store.allSongs().map(\.id), [present.id])

        let second = try BackupService.restore(from: data, into: store)
        XCTAssertFalse(second.restoredAnything)
        XCTAssertEqual(second.skippedExisting, 1)
        XCTAssertEqual(try store.allSongs().count, 1)
    }

    func testRestoreRejectsForeignFiles() {
        XCTAssertThrowsError(try BackupService.restore(from: Data("{}".utf8), into: store))
    }

    func testHealthReportFindsMissingAudioAndOrphans() throws {
        _ = makeSong("Fine")
        let broken = makeSong("Broken", withFile: false)
        let orphanName = "orphan-\(UUID().uuidString).mp3"
        writeAudio(orphanName)

        let report = store.healthReport()
        XCTAssertTrue(report.missingAudio.contains { $0.songID == broken.id })
        XCTAssertTrue(report.orphanAudioFiles.contains(orphanName))

        store.deleteOrphans(audio: [orphanName], artwork: [])
        XCTAssertFalse(store.healthReport().orphanAudioFiles.contains(orphanName))
    }

    func testRemoveMissingAudioDropsEmptiedSongsButKeepsOthers() throws {
        let fine = makeSong("Fine")
        let broken = makeSong("Broken", withFile: false)
        let multi = makeSong("Multi")
        let lostVersion = SongVersion(name: "Demo", fileName: "lost-\(UUID().uuidString).m4a", pcmHash: UUID().uuidString, duration: 50)
        lostVersion.song = multi
        multi.versions.append(lostVersion)

        let removed = store.removeMissingAudio(store.healthReport().missingAudio)

        XCTAssertEqual(removed, 2)
        let ids = Set(try store.allSongs().map(\.id))
        XCTAssertTrue(ids.contains(fine.id) && ids.contains(multi.id))
        XCTAssertFalse(ids.contains(broken.id))
        XCTAssertEqual(multi.versions.count, 1)
    }

    func testMergeDuplicatesFoldsCopiesIntoOldestSong() throws {
        let first = makeSong("Twin")
        first.dateAdded = Date(timeIntervalSince1970: 100)
        let second = makeSong("Twin")
        second.dateAdded = Date(timeIntervalSince1970: 200)

        let group = try XCTUnwrap(store.healthReport().duplicates.first { $0.title == "Twin" })
        store.mergeDuplicates(songIDs: group.songIDs)

        let twins = try store.allSongs().filter { $0.title == "Twin" }
        XCTAssertEqual(twins.count, 1)
        XCTAssertEqual(twins.first?.id, first.id)
        XCTAssertEqual(twins.first?.versions.count, 2)
    }
}

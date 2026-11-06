import XCTest
import SwiftData
@testable import Era

@MainActor
final class StoreTests: XCTestCase {
    private var store: EraStore!

    override func setUp() async throws {
        let container = Persistence.makeContainer(inMemory: true)
        store = EraStore(context: ModelContext(container))
    }

    private func makeSong(_ title: String, hash: String = UUID().uuidString, duration: Double = 120) -> Song {
        let song = Song(title: title)
        let version = SongVersion(name: "OG", fileName: "\(title).m4a", pcmHash: hash, duration: duration)
        version.song = song
        song.versions.append(version)
        song.primaryVersionID = version.id
        store.insertSong(song)
        return song
    }

    func testVersionMatchingNeedsHashAndSimilarDuration() throws {
        _ = makeSong("A", hash: "abc", duration: 100)
        XCTAssertNotNil(try store.version(matchingHash: "abc", duration: 100.3))
        XCTAssertNil(try store.version(matchingHash: "abc", duration: 105))
        XCTAssertNil(try store.version(matchingHash: "other", duration: 100))
    }

    func testMergeMovesVersionsAndTagsAndRemovesSource() throws {
        let target = makeSong("Target")
        let source = makeSong("Source")
        let tag = store.makeTag(named: "demo")
        source.tags.append(tag)

        store.mergeSongAsVersions(source, into: target)

        XCTAssertEqual(try store.allSongs().count, 1)
        XCTAssertEqual(target.versions.count, 2)
        XCTAssertTrue(target.tags.contains { $0.id == tag.id })
        XCTAssertEqual(Set(target.versions.map(\.sortIndex)).count, 2)
    }

    func testMergeIntoSelfIsNoOp() throws {
        let song = makeSong("Solo")
        store.mergeSongAsVersions(song, into: song)
        XCTAssertEqual(try store.allSongs().count, 1)
        XCTAssertEqual(song.versions.count, 1)
    }

    func testPlaylistRefusesDuplicatesAndReindexesOnRemove() throws {
        let a = makeSong("A"), b = makeSong("B"), c = makeSong("C")
        let playlist = Playlist(name: "P")
        store.insertPlaylist(playlist)
        for song in [a, b, c] { store.appendEntry(song: song, version: nil, to: playlist) }
        store.appendEntry(song: a, version: nil, to: playlist)
        XCTAssertEqual(playlist.entries.count, 3)

        let middle = try XCTUnwrap(playlist.sortedEntries.first { $0.song?.id == b.id })
        store.removeEntry(middle, from: playlist)
        XCTAssertEqual(playlist.sortedEntries.map(\.position), [0, 1])
        XCTAssertEqual(playlist.sortedEntries.compactMap { $0.song?.title }, ["A", "C"])
    }

    func testTagLookupIsCaseInsensitiveAndNotDuplicated() throws {
        let first = store.makeTag(named: "Sketch")
        let second = store.makeTag(named: "sketch")
        XCTAssertEqual(first.id, second.id)
    }

    func testStatusTagsAreEnsuredOnce() throws {
        store.ensureStatusTags()
        store.ensureStatusTags()
        XCTAssertEqual(try store.allTags().filter(\.isStatus).count, StatusTag.all.count)
    }

    func testBackupExportRoundtripsLibraryContent() throws {
        let song = makeSong("Backup Me")
        song.isFavorite = true
        let url = try BackupService.exportURL(store: store)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LibraryBackup.self, from: Data(contentsOf: url))
        XCTAssertEqual(backup.songs.count, 1)
        XCTAssertEqual(backup.songs.first?.title, "Backup Me")
        XCTAssertEqual(backup.songs.first?.isFavorite, true)
        XCTAssertEqual(backup.versions.first?.songID, song.id)
    }

    func testBackupIncludesPlayEvents() throws {
        _ = makeSong("Heard")
        store.context.insert(PlayEvent(date: Date(), seconds: 90, songID: nil, title: "Heard", artist: "X"))
        store.save()
        let backup = try BackupService.makeBackup(store: store)
        XCTAssertEqual(backup.formatVersion, LibraryBackup.currentFormatVersion)
        XCTAssertEqual(backup.playEvents?.count, 1)
    }

    func testDecodeRejectsForeignAndNewerFiles() throws {
        XCTAssertThrowsError(try BackupService.decode(Data("{\"hello\":1}".utf8)))
        var future = try BackupService.makeBackup(store: store)
        future.formatVersion = 99
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertThrowsError(try BackupService.decode(try encoder.encode(future)))
    }

    func testRestoreRebuildsLibraryIntoEmptyStoreWhenAudioExists() throws {
        let song = makeSong("Round Trip")
        song.isFavorite = true
        song.tags.append(store.makeTag(named: "keeper"))
        let playlist = Playlist(name: "Mix")
        store.insertPlaylist(playlist)
        store.appendEntry(song: song, version: song.primaryVersion, to: playlist)
        store.context.insert(PlayEvent(date: Date(), seconds: 60, songID: song.id, title: "Round Trip", artist: ""))
        store.save()
        let backup = try BackupService.makeBackup(store: store)

        let fresh = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
        let summary = try BackupService.restore(backup, into: fresh, audioExists: { _ in true })

        XCTAssertEqual(summary.songsAdded, 1)
        XCTAssertEqual(summary.versionsAdded, 1)
        XCTAssertEqual(summary.playlistsAdded, 1)
        XCTAssertEqual(summary.eventsAdded, 1)
        let restored = try XCTUnwrap(try fresh.allSongs().first)
        XCTAssertEqual(restored.id, song.id)
        XCTAssertTrue(restored.isFavorite)
        XCTAssertEqual(restored.tags.map(\.name), ["keeper"])
        XCTAssertEqual(restored.primaryVersionID, song.primaryVersionID)
        XCTAssertEqual(try fresh.allPlaylists().first?.entries.count, 1)
    }

    func testRestoreIsIdempotentAndSkipsMissingAudio() throws {
        _ = makeSong("Once")
        let backup = try BackupService.makeBackup(store: store)

        // Same store: everything already exists.
        let again = try BackupService.restore(backup, into: store, audioExists: { _ in true })
        XCTAssertEqual(again.songsAdded, 0)
        XCTAssertEqual(try store.allSongs().count, 1)

        // Empty store without audio files: song is skipped, not restored as a broken entry.
        let fresh = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
        let skipped = try BackupService.restore(backup, into: fresh, audioExists: { _ in false })
        XCTAssertEqual(skipped.songsAdded, 0)
        XCTAssertEqual(skipped.songsSkippedMissingAudio, 1)
        XCTAssertTrue(try fresh.allSongs().isEmpty)
    }
}

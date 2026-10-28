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

    private func addVersion(_ name: String, to song: Song) -> SongVersion {
        let version = SongVersion(name: name, fileName: "\(song.title)-\(name).m4a", pcmHash: UUID().uuidString, duration: 90)
        version.song = song
        song.versions.append(version)
        return version
    }

    func testRenameVersionTrimsAndIgnoresBlank() throws {
        let song = makeSong("R")
        let version = try XCTUnwrap(song.primaryVersion)
        XCTAssertFalse(store.renameVersion(version, to: "   "))
        XCTAssertEqual(version.name, "OG")
        XCTAssertTrue(store.renameVersion(version, to: "  V2  "))
        XCTAssertEqual(version.name, "V2")
    }

    func testDeleteVersionKeepsLastAndFixesPrimaryAndEntries() throws {
        let song = makeSong("D")
        let first = try XCTUnwrap(song.primaryVersion)
        let second = addVersion("Demo", to: song)
        let playlist = Playlist(name: "P")
        store.insertPlaylist(playlist)
        store.appendEntry(song: song, version: first, to: playlist)

        store.deleteVersion(first)
        XCTAssertEqual(song.versions.map(\.id), [second.id])
        XCTAssertEqual(song.primaryVersion?.id, second.id)
        XCTAssertNil(playlist.entries.first?.versionID)

        store.deleteVersion(second)
        XCTAssertEqual(song.versions.count, 1, "the last version must survive")
    }

    func testSeparateVersionCreatesNewSongAndMovesEntries() throws {
        let song = makeSong("S")
        let first = try XCTUnwrap(song.primaryVersion)
        let second = addVersion("Live", to: song)
        let playlist = Playlist(name: "P")
        store.insertPlaylist(playlist)
        store.appendEntry(song: song, version: second, to: playlist)

        let newSong = try XCTUnwrap(store.separateVersion(second))
        XCTAssertEqual(try store.allSongs().count, 2)
        XCTAssertEqual(song.versions.map(\.id), [first.id])
        XCTAssertEqual(newSong.primaryVersion?.id, second.id)
        XCTAssertEqual(playlist.entries.first?.song?.id, newSong.id)
        XCTAssertNil(store.separateVersion(first), "a single version cannot be detached")
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
}

final class CSVExportTests: XCTestCase {
    func testEscapeQuotesSpecialCharacters() {
        XCTAssertEqual(CSVExport.escape("plain"), "plain")
        XCTAssertEqual(CSVExport.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVExport.escape("two\nlines"), "\"two\nlines\"")
    }

    func testCSVHasHeaderAndOneRowPerSong() {
        let song = Song(title: "Hello, World", artist: "Me", year: 2024)
        let lines = CSVExport.csv(songs: [song]).components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 3) // Header, Zeile, leerer Rest nach letztem Umbruch
        XCTAssertTrue(lines[0].hasPrefix("Title,Artist,Album"))
        XCTAssertTrue(lines[1].hasPrefix("\"Hello, World\",Me,,,2024,"))
    }
}

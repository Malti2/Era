import XCTest
import SwiftData
@testable import Era

@MainActor
final class PlaylistStoreTests: XCTestCase {
    private var store: EraStore!

    override func setUp() async throws {
        store = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
    }

    private func makeSong(_ title: String, duration: Double = 100) -> Song {
        let song = Song(title: title)
        let version = SongVersion(name: "OG", fileName: "\(title).m4a", pcmHash: UUID().uuidString, duration: duration)
        version.song = song
        song.versions.append(version)
        song.primaryVersionID = version.id
        store.insertSong(song)
        return song
    }

    func testCreatePlaylistTrimsAndRefusesBlank() {
        XCTAssertNil(store.createPlaylist(named: "   "))
        XCTAssertEqual(store.createPlaylist(named: "  Road Trip ")?.name, "Road Trip")
    }

    func testCreatePlaylistWithSongsKeepsOrder() throws {
        let a = makeSong("A"), b = makeSong("B")
        let playlist = try XCTUnwrap(store.createPlaylist(named: "P", songs: [b, a]))
        XCTAssertEqual(playlist.sortedEntries.compactMap { $0.song?.title }, ["B", "A"])
    }

    func testAddSongsSkipsDuplicatesAndReportsCount() throws {
        let a = makeSong("A"), b = makeSong("B")
        let playlist = try XCTUnwrap(store.createPlaylist(named: "P", songs: [a]))
        XCTAssertEqual(store.addSongs([a, b], to: playlist), 1)
        XCTAssertEqual(store.addSongs([a, b], to: playlist), 0)
        XCTAssertEqual(playlist.entries.count, 2)
        XCTAssertEqual(playlist.sortedEntries.map(\.position), [0, 1])
    }

    func testRenamePlaylist() throws {
        let playlist = try XCTUnwrap(store.createPlaylist(named: "Old"))
        XCTAssertFalse(store.renamePlaylist(playlist, to: "  "))
        XCTAssertFalse(store.renamePlaylist(playlist, to: "Old"))
        XCTAssertTrue(store.renamePlaylist(playlist, to: " New "))
        XCTAssertEqual(playlist.name, "New")
    }

    func testMoveEntriesReindexesPositions() throws {
        let songs = ["A", "B", "C", "D"].map { makeSong($0) }
        let playlist = try XCTUnwrap(store.createPlaylist(named: "P", songs: songs))
        store.moveEntries(in: playlist, from: [0], to: 3)
        XCTAssertEqual(playlist.sortedEntries.compactMap { $0.song?.title }, ["B", "C", "A", "D"])
        XCTAssertEqual(playlist.sortedEntries.map(\.position), [0, 1, 2, 3])
        store.moveEntries(in: playlist, from: [3], to: 0)
        XCTAssertEqual(playlist.sortedEntries.compactMap { $0.song?.title }, ["D", "B", "C", "A"])
    }

    func testTotalDurationSumsResolvedVersions() throws {
        let playlist = try XCTUnwrap(store.createPlaylist(named: "P", songs: [makeSong("A", duration: 60), makeSong("B", duration: 90)]))
        XCTAssertEqual(playlist.totalDuration, 150, accuracy: 0.01)
    }
}

@MainActor
final class QueuePlaylistTests: XCTestCase {
    private var store: EraStore!

    override func setUp() async throws {
        store = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
    }

    private func makeSong(_ title: String, extraVersion: Bool = false) -> Song {
        let song = Song(title: title)
        for name in extraVersion ? ["OG", "Demo"] : ["OG"] {
            let version = SongVersion(name: name, fileName: "\(title)-\(name).m4a", pcmHash: UUID().uuidString, duration: 100)
            version.song = song
            song.versions.append(version)
        }
        song.primaryVersionID = song.versions.first?.id
        store.insertSong(song)
        return song
    }

    func testQueueBecomesPlaylistInOrderWithChosenVersions() throws {
        let a = makeSong("A", extraVersion: true), b = makeSong("B")
        let demo = try XCTUnwrap(a.versions.first { $0.name == "Demo" })
        let playlist = try XCTUnwrap(store.createPlaylist(named: " Mix ", fromQueue: [b.versions[0], demo]))
        XCTAssertEqual(playlist.name, "Mix")
        XCTAssertEqual(playlist.sortedEntries.compactMap { $0.song?.title }, ["B", "A"])
        XCTAssertEqual(playlist.sortedEntries.last?.versionID, demo.id)
    }

    func testSongQueuedTwiceIsAddedOnce() throws {
        let a = makeSong("A")
        let playlist = try XCTUnwrap(store.createPlaylist(named: "P", fromQueue: [a.versions[0], a.versions[0]]))
        XCTAssertEqual(playlist.entries.count, 1)
    }

    func testBlankNameOrEmptyQueueCreatesNothing() throws {
        let a = makeSong("A")
        XCTAssertNil(store.createPlaylist(named: "  ", fromQueue: [a.versions[0]]))
        XCTAssertNil(store.createPlaylist(named: "P", fromQueue: []))
        XCTAssertTrue(try store.allPlaylists().isEmpty)
    }
}

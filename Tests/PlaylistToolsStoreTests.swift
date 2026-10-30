import XCTest
import SwiftData
@testable import Era

@MainActor
final class PlaylistToolsStoreTests: XCTestCase {
    private var store: EraStore!

    override func setUp() async throws {
        store = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
    }

    private func makePlaylist(_ songs: [(String, String, Double)]) -> Playlist {
        let playlist = store.createPlaylist(named: "P")!
        for (title, artist, duration) in songs {
            let song = Song(title: title, artist: artist)
            let version = SongVersion(name: "OG", fileName: "\(title).m4a", pcmHash: UUID().uuidString, duration: duration)
            version.song = song
            song.versions.append(version)
            song.primaryVersionID = version.id
            store.insertSong(song)
            store.appendEntry(song: song, version: version, to: playlist)
        }
        return playlist
    }

    private func titles(_ playlist: Playlist) -> [String] { playlist.sortedEntries.compactMap { $0.song?.title } }

    func testSortPlaylistWritesNewPositions() {
        let playlist = makePlaylist([("Beta", "Zed", 300), ("Alpha", "Yan", 100), ("Gamma", "Abe", 200)])
        store.sortPlaylist(playlist, by: .title)
        XCTAssertEqual(titles(playlist), ["Alpha", "Beta", "Gamma"])
        store.sortPlaylist(playlist, by: .artist)
        XCTAssertEqual(titles(playlist), ["Gamma", "Alpha", "Beta"])
        store.sortPlaylist(playlist, by: .longest)
        XCTAssertEqual(titles(playlist), ["Beta", "Gamma", "Alpha"])
        store.sortPlaylist(playlist, by: .reverse)
        XCTAssertEqual(titles(playlist), ["Alpha", "Gamma", "Beta"])
        XCTAssertEqual(playlist.sortedEntries.map(\.position), [0, 1, 2])
    }

    func testDuplicateKeepsOrderAndIsIndependent() throws {
        let playlist = makePlaylist([("A", "x", 60), ("B", "x", 90)])
        let copy = try XCTUnwrap(store.duplicatePlaylist(playlist, named: "P Copy"))
        XCTAssertEqual(copy.name, "P Copy")
        XCTAssertEqual(titles(copy), ["A", "B"])
        store.removeEntry(copy.sortedEntries[0], from: copy)
        XCTAssertEqual(titles(playlist), ["A", "B"])
        XCTAssertEqual(try store.allPlaylists().count, 2)
    }

    func testDuplicateRefusesBlankName() {
        let playlist = makePlaylist([("A", "x", 60)])
        XCTAssertNil(store.duplicatePlaylist(playlist, named: "  "))
    }
}

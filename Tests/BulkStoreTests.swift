import XCTest
import SwiftData
@testable import Era

@MainActor
final class BulkStoreTests: XCTestCase {
    private var store: EraStore!

    override func setUp() async throws {
        store = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
    }

    private func makeSong(_ title: String) -> Song {
        let song = Song(title: title)
        let version = SongVersion(name: "OG", fileName: "\(UUID().uuidString).m4a", pcmHash: UUID().uuidString, duration: 100)
        version.song = song
        song.versions.append(version)
        song.primaryVersionID = version.id
        store.insertSong(song)
        return song
    }

    func testFavoriteAndTagInBulkAreIdempotent() {
        let a = makeSong("A"), b = makeSong("B")
        let tag = store.makeTag(named: "sketch")
        store.setFavorite(true, for: [a, b])
        store.add(tag, to: [a, b])
        store.add(tag, to: [a])
        XCTAssertTrue(a.isFavorite && b.isFavorite)
        XCTAssertEqual(a.tags.count, 1)

        store.remove(tag, from: [a])
        XCTAssertTrue(a.tags.isEmpty)
        XCTAssertEqual(b.tags.count, 1)
    }

    func testDeleteSongsRemovesAllOfThem() throws {
        let a = makeSong("A"), b = makeSong("B"), c = makeSong("C")
        store.deleteSongs([a, b])
        XCTAssertEqual(try store.allSongs().map(\.title), [c.title])
    }

    func testRenameTagPlain() throws {
        let tag = store.makeTag(named: "demo")
        XCTAssertEqual(store.renameTag(tag, to: "  Rough  "), .rename(to: "Rough"))
        XCTAssertEqual(tag.name, "Rough")
        XCTAssertEqual(store.renameTag(tag, to: " "), .invalid)
    }

    func testRenameIntoExistingTagMergesSongsAndFilters() throws {
        let a = makeSong("A"), b = makeSong("B")
        let old = store.makeTag(named: "sketch")
        let target = store.makeTag(named: "Demo")
        store.add(old, to: [a, b])
        store.add(target, to: [b])
        let pack = Pack(name: "P", tagIDs: [old.id, target.id])
        store.insertPack(pack)
        let playlist = Playlist(name: "Smart")
        playlist.filterTagIDs = [old.id]
        store.insertPlaylist(playlist)

        XCTAssertEqual(store.renameTag(old, to: "demo"), .merge(into: "Demo"))

        XCTAssertEqual(try store.allTags().filter { !$0.isStatus }.map(\.name), ["Demo"])
        XCTAssertEqual(a.tags.map(\.name), ["Demo"])
        XCTAssertEqual(b.tags.count, 1)
        XCTAssertEqual(pack.tagIDs, [target.id])
        XCTAssertEqual(playlist.filterTagIDs, [target.id])
    }

    func testStatusTagsCannotBeRenamed() throws {
        store.ensureStatusTags()
        let demo = try XCTUnwrap(try store.tag(named: "Demo"))
        XCTAssertEqual(store.renameTag(demo, to: "Other"), .invalid)
        XCTAssertEqual(demo.name, "Demo")
    }

    func testUnusedTagsIgnoreTagsStillReferenced() throws {
        store.ensureStatusTags()
        let song = makeSong("A")
        let used = store.makeTag(named: "used")
        let inPack = store.makeTag(named: "inpack")
        _ = store.makeTag(named: "orphan")
        store.add(used, to: [song])
        store.insertPack(Pack(name: "Pack", tagIDs: [inPack.id]))

        XCTAssertEqual(store.unusedTags().map(\.name), ["orphan"])
        XCTAssertEqual(store.deleteUnusedTags(), 1)
        XCTAssertNil(try store.tag(named: "orphan"))
        XCTAssertNotNil(try store.tag(named: "inpack"))
    }

    func testDeleteTagEverywhereCleansReferences() throws {
        let song = makeSong("A")
        let tag = store.makeTag(named: "gone")
        store.add(tag, to: [song])
        let pack = Pack(name: "P", tagIDs: [tag.id])
        store.insertPack(pack)

        store.deleteTagEverywhere(tag)

        XCTAssertTrue(song.tags.isEmpty)
        XCTAssertTrue(pack.tagIDs.isEmpty)
        XCTAssertNil(try store.tag(named: "gone"))
    }
}

import XCTest
import SwiftData
@testable import Era

@MainActor
final class MarkerStoreTests: XCTestCase {
    private var store: EraStore!

    override func setUp() async throws {
        store = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
    }

    private func makeSong(title: String = "Sketch") -> Song {
        let song = Song(title: title)
        let version = SongVersion(name: "OG", fileName: "\(title).m4a", pcmHash: UUID().uuidString, duration: 120)
        version.song = song
        song.versions.append(version)
        song.primaryVersionID = version.id
        store.insertSong(song)
        return song
    }

    func testNotesAreTrimmedAndChangeIsReported() {
        let song = makeSong()
        XCTAssertTrue(store.setNotes("  Refrain neu singen \n", for: song))
        XCTAssertEqual(song.notes, "Refrain neu singen")
        XCTAssertFalse(store.setNotes("Refrain neu singen", for: song), "unchanged text is not a change")
        XCTAssertTrue(store.setNotes("", for: song))
        XCTAssertEqual(song.notes, "")
    }

    func testMarkersPersistSortedOnTheVersion() throws {
        let version = try XCTUnwrap(makeSong().primaryVersion)
        store.addMarker(at: 80, label: "Outro", to: version)
        store.addMarker(at: 10, label: "Hook", to: version)
        XCTAssertEqual(version.markers.map(\.label), ["Hook", "Outro"])
        XCTAssertFalse(version.markersJSON.isEmpty)
    }

    func testAddingNearExistingMarkerFillsEmptyLabelOnly() throws {
        let version = try XCTUnwrap(makeSong().primaryVersion)
        store.addMarker(at: 30, to: version)
        store.addMarker(at: 30.4, label: "Bridge", to: version)
        XCTAssertEqual(version.markers.count, 1)
        XCTAssertEqual(version.markers.first?.label, "Bridge")
        store.addMarker(at: 30.2, label: "Other", to: version)
        XCTAssertEqual(version.markers.first?.label, "Bridge")
    }

    func testMarkerTimeIsClampedToVersionDuration() throws {
        let version = try XCTUnwrap(makeSong().primaryVersion)
        let marker = store.addMarker(at: 999, to: version)
        XCTAssertEqual(marker?.time, 120)
    }

    func testRenameRemoveAndClear() throws {
        let version = try XCTUnwrap(makeSong().primaryVersion)
        let a = try XCTUnwrap(store.addMarker(at: 5, label: "A", to: version))
        store.addMarker(at: 50, label: "B", to: version)
        store.renameMarker(a.id, to: "Intro", in: version)
        XCTAssertEqual(version.markers.map(\.label), ["Intro", "B"])
        store.removeMarker(a.id, from: version)
        XCTAssertEqual(version.markers.map(\.label), ["B"])
        store.clearMarkers(of: version)
        XCTAssertTrue(version.markers.isEmpty)
        XCTAssertEqual(version.markersJSON, "")
    }

    func testMergeKeepsBothNotes() {
        let target = makeSong(title: "A"), source = makeSong(title: "B")
        target.notes = "alt"
        source.notes = "neu"
        store.mergeSongAsVersions(source, into: target)
        XCTAssertEqual(target.notes, "alt\n\nneu")
        XCTAssertEqual(target.versions.count, 2)
    }

    func testSearchAdapterIncludesNotesAndMarkerLabels() throws {
        let song = makeSong()
        store.setNotes("Gitarrenriff", for: song)
        store.addMarker(at: 20, label: "Beat Drop", to: try XCTUnwrap(song.primaryVersion))
        XCTAssertEqual(song.searchable.notes, "Gitarrenriff")
        XCTAssertEqual(song.searchable.markerLabels, ["Beat Drop"])
    }
}

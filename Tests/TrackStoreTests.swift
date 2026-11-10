import XCTest
import SwiftData
@testable import Era

@MainActor
final class TrackStoreTests: XCTestCase {
    private var store: EraStore!

    override func setUp() async throws {
        store = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
    }

    private func makeSong(_ title: String, track: Int = 0, added: Double = 0) -> Song {
        let song = Song(title: title, album: "Album")
        song.trackNumber = track
        song.dateAdded = Date(timeIntervalSince1970: added)
        store.insertSong(song)
        return song
    }

    func testTrackOrderPutsNumberedSongsFirst() {
        let a = makeSong("A", track: 0, added: 5), b = makeSong("B", track: 2), c = makeSong("C", track: 1)
        XCTAssertEqual(EraStore.inTrackOrder([a, b, c]).map(\.title), ["C", "B", "A"])
    }

    func testApplyTrackOrderNumbersFromOne() {
        let a = makeSong("A"), b = makeSong("B"), c = makeSong("C")
        XCTAssertEqual(store.applyTrackOrder([c, a, b]), 3)
        XCTAssertEqual([c.trackNumber, a.trackNumber, b.trackNumber], [1, 2, 3])
        XCTAssertEqual(store.applyTrackOrder([c, a, b]), 0, "unchanged order is a no-op")
    }

    func testClearTrackNumbers() {
        let a = makeSong("A", track: 1), b = makeSong("B")
        XCTAssertEqual(store.clearTrackNumbers(of: [a, b]), 1)
        XCTAssertEqual(a.trackNumber, 0)
    }

    func testBackupRoundTripKeepsTrackNumber() throws {
        _ = makeSong("A", track: 4)
        let exported = try BackupService.exportURL(store: store)
        let data = try Data(contentsOf: exported)
        let decoded = try LibraryBackup.decode(from: data)
        XCTAssertEqual(decoded.songs.first?.trackNumber, 4)
    }
}

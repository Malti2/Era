import XCTest
import SwiftData
@testable import Era

@MainActor
final class ArtworkStoreTests: XCTestCase {
    private var store: EraStore!
    private var directory: URL!

    override func setUp() async throws {
        store = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("EraArt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeVersion() -> SongVersion {
        let song = Song(title: "Cover Me")
        let version = SongVersion(name: "OG", fileName: "a.m4a", pcmHash: "h", duration: 60)
        version.song = song
        song.versions.append(version)
        song.primaryVersionID = version.id
        store.insertSong(song)
        return version
    }

    private func files() -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted() }

    func testSetArtworkWritesFileAndReplacesPrevious() {
        let version = makeVersion()
        XCTAssertTrue(store.setArtwork(Data([1, 2, 3]), for: version, directory: directory))
        let first = version.artworkFile
        XCTAssertNotNil(first)
        XCTAssertEqual(files(), [first!])

        XCTAssertTrue(store.setArtwork(Data([4, 5]), for: version, directory: directory))
        XCTAssertNotEqual(version.artworkFile, first, "new name avoids stale cache entries")
        XCTAssertEqual(files(), [version.artworkFile!], "old file is removed")
    }

    func testClearArtworkRemovesFileAndReference() {
        let version = makeVersion()
        store.setArtwork(Data([9]), for: version, directory: directory)
        store.clearArtwork(for: version, directory: directory)
        XCTAssertNil(version.artworkFile)
        XCTAssertTrue(files().isEmpty)
    }

    func testSetArtworkFailsGracefullyWithoutDirectory() {
        let version = makeVersion()
        let missing = directory.appendingPathComponent("nope")
        XCTAssertFalse(store.setArtwork(Data([1]), for: version, directory: missing))
        XCTAssertNil(version.artworkFile)
    }
}

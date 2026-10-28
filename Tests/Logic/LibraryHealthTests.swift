import XCTest
@testable import Era

final class LibraryHealthTests: XCTestCase {
    private func song(_ title: String, artist: String = "", versions: [(String, String?)]) -> HealthSong {
        HealthSong(id: UUID(), title: title, artist: artist,
                   versions: versions.map { HealthVersion(id: UUID(), name: "OG", fileName: $0.0, artworkFile: $0.1) })
    }

    func testHealthyLibraryHasNoFindings() {
        let a = song("A", versions: [("a.m4a", "a.img")])
        let files = LibraryFilesSnapshot(audio: ["a.m4a": 10], artwork: ["a.img": 2])
        let report = LibraryHealth.analyze(songs: [a], files: files)
        XCTAssertTrue(report.isHealthy)
    }

    func testFindsMissingAudioAndEmptySongs() {
        let a = song("A", versions: [("a.m4a", nil), ("gone.m4a", nil)])
        let empty = song("Empty", versions: [])
        let report = LibraryHealth.analyze(songs: [a, empty], files: LibraryFilesSnapshot(audio: ["a.m4a": 1]))
        XCTAssertEqual(report.missingAudio.map(\.songID), [a.id])
        XCTAssertEqual(report.missingAudio.first?.versionID, a.versions[1].id)
        XCTAssertEqual(report.emptySongIDs, [empty.id])
        XCTAssertFalse(report.isHealthy)
    }

    func testOrphansIgnoreNonAudioFilesAndCountBytes() {
        let a = song("A", versions: [("a.m4a", "a.img")])
        let files = LibraryFilesSnapshot(
            audio: ["a.m4a": 10, "stray.mp3": 500, "library-v3-migriert.json": 99, ".DS_Store": 1],
            artwork: ["a.img": 2, "old.img": 30])
        let report = LibraryHealth.analyze(songs: [a], files: files)
        XCTAssertEqual(report.orphanAudioFiles, ["stray.mp3"])
        XCTAssertEqual(report.orphanArtworkFiles, ["old.img"])
        XCTAssertEqual(report.orphanBytes, 530)
        XCTAssertEqual(report.orphanCount, 2)
    }

    func testBrokenArtworkReferenceIsReported() {
        let a = song("A", versions: [("a.m4a", "lost.img")])
        let report = LibraryHealth.analyze(songs: [a], files: LibraryFilesSnapshot(audio: ["a.m4a": 1]))
        XCTAssertEqual(report.brokenArtworkVersionIDs, [a.versions[0].id])
    }

    func testDuplicatesIgnoreCaseAccentsAndNeedSameArtist() {
        let one = song("Café", artist: "Neon", versions: [("1.m4a", nil)])
        let two = song("cafe", artist: "NEON", versions: [("2.m4a", nil)])
        let other = song("Cafe", artist: "Someone Else", versions: [("3.m4a", nil)])
        let files = LibraryFilesSnapshot(audio: ["1.m4a": 1, "2.m4a": 1, "3.m4a": 1])
        let report = LibraryHealth.analyze(songs: [one, two, other], files: files)
        XCTAssertEqual(report.duplicates.count, 1)
        XCTAssertEqual(Set(report.duplicates[0].songIDs), [one.id, two.id])
    }
}

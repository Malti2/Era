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

    func testSimilarTitlesAreHintsNotProblems() {
        let base = song("Sunrise", artist: "Mira", versions: [("1.m4a", nil)])
        let demo = song("Sunrise (Demo)", artist: "Mira", versions: [("2.m4a", nil)])
        let unrelated = song("Moonlight", artist: "Mira", versions: [("3.m4a", nil)])
        let files = LibraryFilesSnapshot(audio: ["1.m4a": 1, "2.m4a": 1, "3.m4a": 1])
        let report = LibraryHealth.analyze(songs: [base, demo, unrelated], files: files)
        XCTAssertTrue(report.isHealthy, "similar titles never make the library unhealthy")
        XCTAssertTrue(report.duplicates.isEmpty)
        XCTAssertEqual(report.similar.count, 1)
        XCTAssertEqual(report.similar[0].title, "Sunrise", "the shortest title names the group")
        XCTAssertEqual(Set(report.similar[0].songIDs), [base.id, demo.id])
    }

    func testIgnoredSimilarGroupsAreHidden() {
        let base = song("Sunrise", versions: [("1.m4a", nil)])
        let demo = song("Sunrise v2", versions: [("2.m4a", nil)])
        let report = LibraryHealth.analyze(songs: [base, demo], files: LibraryFilesSnapshot(audio: ["1.m4a": 1, "2.m4a": 1]))
        XCTAssertEqual(report.visibleSimilar(ignoring: []).count, 1)
        let key = LibraryHealthReport.groupKey([demo.id, base.id])
        XCTAssertEqual(key, LibraryHealthReport.groupKey([base.id, demo.id]), "order does not matter")
        XCTAssertTrue(report.visibleSimilar(ignoring: [key]).isEmpty)
    }

    // MARK: Track-Nummern je Disc

    private func albumSong(_ title: String, album: String, track: Int, disc: Int = 0) -> HealthSong {
        var s = song(title, versions: [("\(title).m4a", nil)])
        s.album = album
        s.trackNumber = track
        s.discNumber = disc
        return s
    }

    private func files(for songs: [HealthSong]) -> LibraryFilesSnapshot {
        LibraryFilesSnapshot(audio: Dictionary(uniqueKeysWithValues: songs.flatMap { $0.versions.map { ($0.fileName, 1) } }))
    }

    func testMultiDiscAlbumWithSameTrackNumbersIsHealthy() {
        // Frueher ein falscher Fund: Track 1 auf Disc 1 und Disc 2 zaehlte als Duplikat.
        let songs = [
            albumSong("A1", album: "Double", track: 1, disc: 1),
            albumSong("A2", album: "Double", track: 2, disc: 1),
            albumSong("B1", album: "Double", track: 1, disc: 2),
            albumSong("B2", album: "Double", track: 2, disc: 2),
        ]
        let report = LibraryHealth.analyze(songs: songs, files: files(for: songs))
        XCTAssertTrue(report.trackIssues.isEmpty)
        XCTAssertTrue(report.isHealthy)
    }

    func testMissingDiscIsReported() {
        let songs = [
            albumSong("B1", album: "Double", track: 1, disc: 2),
            albumSong("B2", album: "Double", track: 2, disc: 2),
        ]
        let report = LibraryHealth.analyze(songs: songs, files: files(for: songs))
        XCTAssertEqual(report.trackIssues.count, 1)
        XCTAssertEqual(report.trackIssues[0].missingDiscs, [1])
        XCTAssertTrue(report.trackIssues[0].discs.isEmpty)
        XCTAssertFalse(report.trackIssues[0].fixableByRenumbering, "only a missing disc – renumbering fixes nothing")
        XCTAssertFalse(report.isHealthy)
    }

    func testPerDiscMissingAndDuplicatesAreSeparate() {
        let songs = [
            albumSong("A1", album: "Double", track: 1, disc: 1),
            albumSong("A3", album: "Double", track: 3, disc: 1),
            albumSong("B1", album: "Double", track: 1, disc: 2),
            albumSong("B1b", album: "Double", track: 1, disc: 2),
            albumSong("B2", album: "Double", track: 2, disc: 2),
        ]
        let report = LibraryHealth.analyze(songs: songs, files: files(for: songs))
        XCTAssertEqual(report.trackIssues.count, 1)
        let issue = report.trackIssues[0]
        XCTAssertEqual(issue.discs, [
            .init(disc: 1, duplicates: [], missing: [2]),
            .init(disc: 2, duplicates: [1], missing: []),
        ])
        XCTAssertEqual(issue.duplicates, [1])
        XCTAssertEqual(issue.missing, [2])
        XCTAssertTrue(issue.missingDiscs.isEmpty)
        XCTAssertTrue(issue.fixableByRenumbering, "gaps and duplicates can be renumbered")
    }

    func testSingleDiscDuplicatesStillReported() {
        let songs = [
            albumSong("A1", album: "Solo", track: 1),
            albumSong("A2", album: "Solo", track: 2),
            albumSong("A2b", album: "Solo", track: 2),
        ]
        let report = LibraryHealth.analyze(songs: songs, files: files(for: songs))
        XCTAssertEqual(report.trackIssues.count, 1)
        XCTAssertEqual(report.trackIssues[0].duplicates, [2])
        XCTAssertEqual(report.trackIssues[0].missing, [])
        XCTAssertEqual(report.trackIssues[0].discs, [.init(disc: 1, duplicates: [2], missing: [])])
    }

    func testSingleTrackOnSecondDiscIsNotAnIssue() {
        let songs = [
            albumSong("B1", album: "Double", track: 1, disc: 2),
            albumSong("A2", album: "Double", track: 2, disc: 1),
            albumSong("A1", album: "Double", track: 1, disc: 1),
        ]
        let report = LibraryHealth.analyze(songs: songs, files: files(for: songs))
        // Disc 1 hat nur Track 1 und 2 - kein Fund; Disc 2 allein reicht nicht.
        XCTAssertTrue(report.trackIssues.isEmpty)
    }
}

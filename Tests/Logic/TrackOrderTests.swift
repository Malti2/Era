import XCTest
@testable import Era

final class TrackNumberParsingTests: XCTestCase {
    func testPlainAndPaddedNumbers() {
        XCTAssertEqual(TrackNumber.parse("3"), 3)
        XCTAssertEqual(TrackNumber.parse("03"), 3)
    }

    func testFractionTakesTheTrackPart() {
        XCTAssertEqual(TrackNumber.parse("3/12"), 3)
        XCTAssertEqual(TrackNumber.parse(" 7 of 10"), 7)
        XCTAssertEqual(TrackNumber.parse("Track 4"), 4)
    }

    func testInvalidInputIsZero() {
        XCTAssertEqual(TrackNumber.parse(nil), 0)
        XCTAssertEqual(TrackNumber.parse(""), 0)
        XCTAssertEqual(TrackNumber.parse("abc"), 0)
        XCTAssertEqual(TrackNumber.parse("0"), 0)
        XCTAssertEqual(TrackNumber.parse("0/10"), 0)
    }

    func testHugeValuesAreCapped() {
        XCTAssertEqual(TrackNumber.parse("123456"), TrackNumber.maximum)
        XCTAssertEqual(TrackNumber.clamp(-4), 0)
        XCTAssertEqual(TrackNumber.clamp(5000), TrackNumber.maximum)
    }

    func testITunesAtom() {
        XCTAssertEqual(TrackNumber.fromITunesData([0, 0, 0, 5, 0, 12, 0, 0]), 5)
        XCTAssertEqual(TrackNumber.fromITunesData([0, 0, 1, 2]), 258)
        XCTAssertEqual(TrackNumber.fromITunesData([0, 0, 0, 0]), 0)
        XCTAssertEqual(TrackNumber.fromITunesData([0, 0]), 0)
    }
}

final class TrackOrderTests: XCTestCase {
    private func item(_ title: String, _ track: Int, added: Double = 0) -> TrackItem {
        TrackItem(trackNumber: track, title: title, dateAdded: Date(timeIntervalSince1970: added))
    }

    func testNumberedFirstThenUnnumberedByImportOrder() {
        let a = item("A", 0, added: 20), b = item("B", 2), c = item("C", 1), d = item("D", 0, added: 10)
        XCTAssertEqual(TrackOrder.sorted([a, b, c, d]), [c.id, b.id, d.id, a.id])
    }

    func testSameNumberFallsBackToTitle() {
        let x = item("Zebra", 1), y = item("Apple", 1)
        XCTAssertEqual(TrackOrder.sorted([x, y]), [y.id, x.id])
    }

    func testEmptyInput() {
        XCTAssertTrue(TrackOrder.sorted([]).isEmpty)
    }

    func testRenumberingReportsOnlyChanges() {
        let a = UUID(), b = UUID(), c = UUID()
        let changes = TrackOrder.renumbered(order: [b, a, c], current: [a: 1, b: 2, c: 3])
        XCTAssertEqual(changes, [b: 1, a: 2])
    }

    func testRenumberingAssignsNumbersToUnnumbered() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(TrackOrder.renumbered(order: [a, b], current: [:]), [a: 1, b: 2])
    }

    func testNextNumber() {
        XCTAssertEqual(TrackOrder.nextNumber(after: []), 1)
        XCTAssertEqual(TrackOrder.nextNumber(after: [1, 4, 2]), 5)
        XCTAssertEqual(TrackOrder.nextNumber(after: [TrackNumber.maximum]), TrackNumber.maximum)
    }

    func testDuplicatesAndGaps() {
        XCTAssertEqual(TrackOrder.duplicates(in: [1, 2, 2, 0, 0]), [2])
        XCTAssertEqual(TrackOrder.missing(in: [1, 3, 5, 0]), [2, 4])
        XCTAssertTrue(TrackOrder.missing(in: [0, 0]).isEmpty)
    }
}

final class TrackHealthTests: XCTestCase {
    private func song(_ title: String, album: String, track: Int) -> HealthSong {
        HealthSong(id: UUID(), title: title, artist: "A", versions: [], album: album, trackNumber: track)
    }

    func testGapAndDuplicateAreReported() {
        let songs = [song("a", album: "LP", track: 1), song("b", album: "LP", track: 3), song("c", album: "LP", track: 3)]
        let issues = LibraryHealth.trackIssues(in: songs)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].missing, [2])
        XCTAssertEqual(issues[0].duplicates, [3])
        XCTAssertEqual(issues[0].songIDs.count, 3)
    }

    func testCleanAlbumHasNoIssue() {
        let songs = [song("a", album: "LP", track: 1), song("b", album: "lp ", track: 2)]
        XCTAssertTrue(LibraryHealth.trackIssues(in: songs).isEmpty)
    }

    func testAlbumsWithOneNumberedSongOrNoNumbersAreIgnored() {
        let songs = [song("a", album: "EP", track: 4), song("b", album: "EP", track: 0), song("c", album: "Loose", track: 0)]
        XCTAssertTrue(LibraryHealth.trackIssues(in: songs).isEmpty)
    }

    func testIssuesMakeTheReportUnhealthy() {
        let songs = [song("a", album: "LP", track: 1), song("b", album: "LP", track: 4)]
        let report = LibraryHealth.analyze(songs: songs, files: LibraryFilesSnapshot())
        XCTAssertFalse(report.isHealthy)
        XCTAssertEqual(report.trackIssues.first?.album, "LP")
    }

    func testNumberListIsTruncated() {
        XCTAssertEqual(TrackNumberList.text([2, 4]), "2, 4")
        XCTAssertEqual(TrackNumberList.text([1, 2, 3, 4, 5, 6, 7, 8], limit: 3), "1, 2, 3 +5")
    }
}

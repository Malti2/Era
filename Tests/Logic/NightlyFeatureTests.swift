import XCTest
@testable import Era

final class StorageReportTests: XCTestCase {
    private func item(_ title: String, _ ext: String, _ bytes: Int64?) -> StorageItem {
        StorageItem(id: UUID(), songID: UUID(), title: title, versionName: "OG", fileExtension: ext, bytes: bytes)
    }

    func testTotalsFormatsAndMissingFiles() {
        let report = StorageReport.make(from: [item("A", "mp3", 4_000), item("B", "wav", 40_000), item("C", "MP3", 2_000), item("D", "m4a", nil)])
        XCTAssertEqual(report.totalBytes, 46_000)
        XCTAssertEqual(report.fileCount, 3)
        XCTAssertEqual(report.missingCount, 1)
        XCTAssertEqual(report.formats.map(\.name), ["WAV", "MP3"])
        XCTAssertEqual(report.formats.last?.count, 2)
        XCTAssertEqual(report.averageBytes, 15_333)
    }

    func testLargestAreSortedAndLimited() {
        let items = (1...8).map { item("T\($0)", "flac", Int64($0) * 1_000) }
        let report = StorageReport.make(from: items, largestLimit: 3)
        XCTAssertEqual(report.largest.map(\.title), ["T8", "T7", "T6"])
        XCTAssertEqual(report.share(of: 36_000), 1, accuracy: 0.0001)
    }

    func testEmptyReport() {
        let report = StorageReport.make(from: [])
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.share(of: 10), 0)
        XCTAssertEqual(report.averageBytes, 0)
    }
}

final class CollectionProfileTests: XCTestCase {
    func testAggregatesAndFindsMostPlayed() {
        let profile = CollectionProfile.make(from: [
            ProfileSong(title: "B", playCount: 3, isFavorite: true, versionCount: 2),
            ProfileSong(title: "A", playCount: 3, isFavorite: false, versionCount: 1),
            ProfileSong(title: "C", playCount: 0, isFavorite: true, versionCount: 1),
        ])
        XCTAssertEqual(profile.songs, 3)
        XCTAssertEqual(profile.versions, 4)
        XCTAssertEqual(profile.plays, 6)
        XCTAssertEqual(profile.favorites, 2)
        XCTAssertEqual(profile.neverPlayed, 1)
        XCTAssertEqual(profile.mostPlayed?.title, "A")
        XCTAssertEqual(profile.mostPlayed?.plays, 3)
    }

    func testNothingPlayedHasNoMostPlayed() {
        let profile = CollectionProfile.make(from: [ProfileSong(title: "X", playCount: 0, isFavorite: false, versionCount: 1)])
        XCTAssertNil(profile.mostPlayed)
        XCTAssertEqual(CollectionProfile.make(from: []), CollectionProfile())
    }
}

final class SavedSearchesTests: XCTestCase {
    func testTogglePinsAndUnpinsCaseInsensitively() {
        var list = SavedSearches.toggling("tag:Demo", in: [])
        XCTAssertEqual(list.map(\.query), ["tag:Demo"])
        XCTAssertTrue(SavedSearches.contains("  TAG:demo ", in: list))
        list = SavedSearches.toggling("tag:demo", in: list)
        XCTAssertTrue(list.isEmpty)
    }

    func testBlankIsIgnoredAndNewestFirstWithLimit() {
        XCTAssertTrue(SavedSearches.toggling("   ", in: []).isEmpty)
        var list: [SavedSearch] = []
        for i in 0..<(SavedSearches.limit + 3) { list = SavedSearches.toggling("q\(i)", in: list) }
        XCTAssertEqual(list.count, SavedSearches.limit)
        XCTAssertEqual(list.first?.query, "q\(SavedSearches.limit + 2)")
    }

    func testEncodeDecodeRoundtripAndGarbage() {
        let list = [SavedSearch(query: "is:fav"), SavedSearch(query: "year:2019")]
        XCTAssertEqual(SavedSearches.decode(SavedSearches.encode(list)), list)
        XCTAssertTrue(SavedSearches.decode(Data("nope".utf8)).isEmpty)
        XCTAssertTrue(SavedSearches.decode(nil).isEmpty)
    }
}

final class QueueSummaryTests: XCTestCase {
    func testCountsOnlyUpcomingAndSubtractsElapsed() {
        let s = QueueSummary.make(durations: [100, 200, 60, 40], currentIndex: 1, currentTime: 50)
        XCTAssertEqual(s.upNextCount, 2)
        XCTAssertEqual(s.remainingSeconds, 250)
    }

    func testNoCurrentCountsEverything() {
        let s = QueueSummary.make(durations: [10, 20], currentIndex: nil, currentTime: 5)
        XCTAssertEqual(s, QueueSummary(upNextCount: 2, remainingSeconds: 30))
    }

    func testLastTrackAndOutOfRange() {
        XCTAssertEqual(QueueSummary.make(durations: [90], currentIndex: 0, currentTime: 100), QueueSummary(upNextCount: 0, remainingSeconds: 0))
        XCTAssertEqual(QueueSummary.make(durations: [90], currentIndex: 5, currentTime: 0).upNextCount, 1)
    }
}

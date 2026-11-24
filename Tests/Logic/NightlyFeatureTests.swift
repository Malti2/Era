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

    func testEmptyExtensionBecomesQuestionMarkAndFormatsTieBreakByName() {
        let report = StorageReport.make(from: [item("A", "", 10), item("B", "Mp3", 10)])
        // Gleiche Bytes -> Name aufsteigend ("?" = 63, "M" = 77)
        XCTAssertEqual(report.formats.map(\.name), ["?", "MP3"])
    }

    func testLargestTieBreaksByTitle() {
        let report = StorageReport.make(from: [item("Zulu", "flac", 100), item("Alpha", "flac", 100)])
        XCTAssertEqual(report.largest.map(\.title), ["Alpha", "Zulu"])
    }

    func testMissingFilesAloneAreNotEmpty() {
        XCTAssertFalse(StorageReport.make(from: [item("A", "flac", nil)]).isEmpty)
    }

    func testShareIsClampedToZeroThroughOne() {
        let report = StorageReport.make(from: [item("A", "flac", 100)])
        XCTAssertEqual(report.share(of: 50), 0.5)
        XCTAssertEqual(report.share(of: 200), 1, "more than the total still fits the bar")
        XCTAssertEqual(report.share(of: -10), 0)
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

    func testEquatableComparesMostPlayed() {
        let a = CollectionProfile.make(from: [ProfileSong(title: "Alpha", playCount: 3, isFavorite: false, versionCount: 1)])
        let b = CollectionProfile.make(from: [ProfileSong(title: "Alpha", playCount: 3, isFavorite: false, versionCount: 1)])
        let c = CollectionProfile.make(from: [ProfileSong(title: "Alpha", playCount: 4, isFavorite: false, versionCount: 1)])
        let d = CollectionProfile.make(from: [ProfileSong(title: "Beta", playCount: 3, isFavorite: false, versionCount: 1)])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
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

    func testChipsHideTheActiveSearch() {
        let list = [SavedSearch(query: "tag:Demo"), SavedSearch(query: "year:2019")]
        XCTAssertEqual(SavedSearches.chips(for: "  TAG:demo ", in: list).map(\.query), ["year:2019"])
        XCTAssertEqual(SavedSearches.chips(for: "other", in: list).map(\.query), ["tag:Demo", "year:2019"])
        XCTAssertEqual(SavedSearches.chips(for: "   ", in: list).map(\.query), ["tag:Demo", "year:2019"])
    }

    func testDedupIgnoresDiacritics() {
        var list: [SavedSearch] = []
        list = SavedSearches.toggling("tag:démo", in: list)
        XCTAssertTrue(SavedSearches.contains("tag:demo", in: list))
        list = SavedSearches.toggling("tag:demo", in: list)
        XCTAssertTrue(list.isEmpty, "toggling the folded twin unpins it")
    }

    func testContainsReturnsFalseForEmptyQuery() {
        XCTAssertFalse(SavedSearches.contains("", in: [SavedSearch(query: "tag:demo")]))
        XCTAssertFalse(SavedSearches.contains("tag:demo", in: []))
    }

    func testDecodeNormalizesLimitAndDuplicates() {
        let many = (0..<15).map { SavedSearch(query: "q\($0)") }
        XCTAssertEqual(SavedSearches.decode(SavedSearches.encode(many)).count, SavedSearches.limit)
        let dupes = [SavedSearch(query: "tag:demo"), SavedSearch(query: "TAG:DEMO"), SavedSearch(query: "is:played")]
        XCTAssertEqual(SavedSearches.decode(SavedSearches.encode(dupes)).map(\.query), ["tag:demo", "is:played"])
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

    func testNegativeCurrentTimeCountsFullCurrentTrack() {
        XCTAssertEqual(QueueSummary.make(durations: [100, 50], currentIndex: 0, currentTime: -10).remainingSeconds, 150)
    }

    func testNegativeAndZeroDurationsAreClamped() {
        let s = QueueSummary.make(durations: [-30, 0, 60], currentIndex: nil, currentTime: 0)
        XCTAssertEqual(s.remainingSeconds, 60)
        XCTAssertEqual(s.upNextCount, 3)
    }

    func testEmptyQueueIsZero() {
        XCTAssertEqual(QueueSummary.make(durations: [], currentIndex: nil, currentTime: 0), QueueSummary(upNextCount: 0, remainingSeconds: 0))
    }
}

final class WeeklyRecapTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_773_835_200) // 12:00 UTC

    private func play(_ daysAgo: Int, _ seconds: Double = 600, title: String = "T") -> PlayRecord {
        PlayRecord(date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!, seconds: seconds, title: title, artist: "A")
    }

    func testWindowsAndZeroFilledDays() {
        let recap = WeeklyRecap.make(from: [play(0), play(0, 300), play(6), play(7), play(13), play(14)], now: now, calendar: calendar)
        XCTAssertEqual(recap.days.count, 7)
        XCTAssertEqual(recap.plays, 3)
        XCTAssertEqual(recap.seconds, 1_500)
        XCTAssertEqual(recap.previousPlays, 2)
        XCTAssertEqual(recap.days.last?.plays, 2)
        XCTAssertEqual(recap.days.first?.plays, 1)
        XCTAssertEqual(recap.days.filter { $0.plays == 0 }.count, 5)
        XCTAssertEqual(recap.barHeight(for: recap.days.last!), 1, accuracy: 0.0001)
    }

    func testTrend() {
        XCTAssertEqual(WeeklyRecap.make(from: [play(0)], now: now, calendar: calendar).trend, .firstWeek)
        XCTAssertEqual(WeeklyRecap.make(from: [play(0, 600), play(8, 600)], now: now, calendar: calendar).trend, .same)
        XCTAssertEqual(WeeklyRecap.make(from: [play(0, 900), play(8, 600)], now: now, calendar: calendar).trend, .up(percent: 50))
        XCTAssertEqual(WeeklyRecap.make(from: [play(0, 300), play(8, 600)], now: now, calendar: calendar).trend, .down(percent: 50))
    }

    func testTopTrackStreakAndEmpty() {
        let recap = WeeklyRecap.make(from: [play(0, title: "X"), play(1, title: "X"), play(2, title: "Y")], now: now, calendar: calendar)
        XCTAssertEqual(recap.topTrack?.title, "X")
        XCTAssertEqual(recap.streak, 3)
        let empty = WeeklyRecap.make(from: [], now: now, calendar: calendar)
        XCTAssertFalse(empty.hasActivity)
        XCTAssertEqual(empty.days.count, 7)
        XCTAssertEqual(empty.barHeight(for: empty.days[0]), 0)
    }

    func testFuturePlaysFallInNeitherWeek() {
        let recap = WeeklyRecap.make(from: [play(-1)], now: now, calendar: calendar)
        XCTAssertEqual(recap.plays, 0)
        XCTAssertEqual(recap.previousPlays, 0)
    }

    func testTrendRoundingAndFullDrop() {
        // +0,4 % rundet auf 0 -> same; diese Woche nichts -> -100 %.
        XCTAssertEqual(WeeklyRecap.make(from: [play(0, 1004), play(8, 1000)], now: now, calendar: calendar).trend, .same)
        XCTAssertEqual(WeeklyRecap.make(from: [play(8, 100)], now: now, calendar: calendar).trend, .down(percent: 100))
    }

    func testTopTrackIgnoresLastWeekEvenWhenItPlayedMore() {
        let recap = WeeklyRecap.make(from: [play(0, 60, title: "This Week"), play(8, 60, title: "Last Week"), play(8, 60, title: "Last Week")], now: now, calendar: calendar)
        XCTAssertEqual(recap.topTrack?.title, "This Week")
    }

    func testStreakRunsFromYesterdayWhenTodayIsEmpty() {
        let recap = WeeklyRecap.make(from: [play(1), play(2)], now: now, calendar: calendar)
        XCTAssertEqual(recap.streak, 2)
    }
}

final class StorageCleanupTests: XCTestCase {
    private func item(_ title: String, _ bytes: Int64?, primary: Bool, siblings: Int = 2) -> StorageItem {
        StorageItem(id: UUID(), songID: UUID(), title: title, versionName: "v", fileExtension: "wav", bytes: bytes,
                    isPrimary: primary, siblingCount: siblings)
    }

    func testOnlyAlternateVersionsWithFilesAreOffered() {
        let items = [item("Main", 90_000, primary: true), item("Alt small", 1_000, primary: false),
                     item("Alt big", 50_000, primary: false), item("Missing", nil, primary: false),
                     item("Lonely", 5_000, primary: false, siblings: 1)]
        let cleanup = StorageCleanup.make(from: items)
        XCTAssertEqual(cleanup.candidates.map(\.title), ["Alt big", "Alt small"])
        XCTAssertEqual(cleanup.reclaimableBytes, 51_000)
        XCTAssertFalse(cleanup.isEmpty)
    }

    func testSelectionSizeAndThreshold() {
        let big = item("Big", 30_000, primary: false), small = item("Small", 2_000, primary: false)
        let cleanup = StorageCleanup.make(from: [big, small])
        XCTAssertEqual(cleanup.bytes(of: [small.id]), 2_000)
        XCTAssertEqual(cleanup.bytes(of: []), 0)
        XCTAssertEqual(cleanup.ids(atLeast: 10_000), [big.id])
    }

    func testEmptyWhenEverythingIsPrimary() {
        XCTAssertTrue(StorageCleanup.make(from: [item("A", 10, primary: true)]).isEmpty)
    }

    func testCleanupTieBreaksByTitleThenVersionName() {
        let a = StorageItem(id: UUID(), songID: UUID(), title: "Same", versionName: "B", fileExtension: "wav", bytes: 100, isPrimary: false, siblingCount: 2)
        let b = StorageItem(id: UUID(), songID: UUID(), title: "Same", versionName: "A", fileExtension: "wav", bytes: 100, isPrimary: false, siblingCount: 2)
        let cleanup = StorageCleanup.make(from: [a, b])
        XCTAssertEqual(cleanup.candidates.map(\.versionName), ["A", "B"])
        XCTAssertEqual(cleanup.ids(atLeast: 100), Set(cleanup.candidates.map(\.id)), "threshold is inclusive")
    }
}

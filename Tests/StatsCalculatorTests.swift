import XCTest
@testable import Era

final class StatsCalculatorTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    // Wednesday, 2026-03-18 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_773_835_200)

    private func calc() -> StatsCalculator { StatsCalculator(calendar: calendar, now: now) }

    private func play(daysAgo: Int, title: String = "T", artist: String = "A", seconds: Double = 60) -> PlayRecord {
        PlayRecord(date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!, seconds: seconds, title: title, artist: artist)
    }

    func testRangeFiltersRecords() {
        let all = [play(daysAgo: 0), play(daysAgo: 6), play(daysAgo: 7), play(daysAgo: 40)]
        XCTAssertEqual(calc().records(all, in: .week).count, 2)
        XCTAssertEqual(calc().records(all, in: .month).count, 3)
        XCTAssertEqual(calc().records(all, in: .all).count, 4)
    }

    func testDailyBucketsAreZeroFilled() {
        let all = [play(daysAgo: 0), play(daysAgo: 0), play(daysAgo: 3)]
        let buckets = calc().buckets(all, range: .week)
        XCTAssertEqual(buckets.count, 7)
        XCTAssertEqual(buckets.last?.plays, 2)
        XCTAssertEqual(buckets.map(\.plays).reduce(0, +), 3)
        XCTAssertEqual(buckets.filter { $0.plays == 0 }.count, 5)
    }

    func testYearBucketsAreMonthly() {
        let buckets = calc().buckets([play(daysAgo: 0), play(daysAgo: 70)], range: .year)
        XCTAssertEqual(buckets.count, 12)
        XCTAssertEqual(buckets.map(\.plays).reduce(0, +), 2)
    }

    func testAllTimeBucketsWithoutRecordsAreEmpty() {
        XCTAssertTrue(calc().buckets([], range: .all).isEmpty)
    }

    func testTopTracksRankByPlaysThenTitle() {
        let records = [play(daysAgo: 0, title: "B"), play(daysAgo: 1, title: "A"), play(daysAgo: 2, title: "C"), play(daysAgo: 3, title: "C")]
        let top = calc().topTracks(records, limit: 2)
        XCTAssertEqual(top.map(\.title), ["C", "A"])
        XCTAssertEqual(top.first?.plays, 2)
    }

    func testTopArtistsAggregateSeconds() {
        let records = [play(daysAgo: 0, artist: "X", seconds: 100), play(daysAgo: 0, artist: "X", seconds: 50), play(daysAgo: 0, artist: "Y")]
        let top = calc().topArtists(records, limit: 5)
        XCTAssertEqual(top.first?.name, "X")
        XCTAssertEqual(top.first?.seconds, 150)
    }

    func testCurrentStreakCountsBackFromTodayOrYesterday() {
        XCTAssertEqual(calc().currentStreak([play(daysAgo: 0), play(daysAgo: 1), play(daysAgo: 2), play(daysAgo: 4)]), 3)
        XCTAssertEqual(calc().currentStreak([play(daysAgo: 1), play(daysAgo: 2)]), 2)
        XCTAssertEqual(calc().currentStreak([play(daysAgo: 2)]), 0)
        XCTAssertEqual(calc().currentStreak([]), 0)
    }

    func testLongestStreak() {
        let records = [0, 1, 5, 6, 7, 8, 20].map { play(daysAgo: $0) }
        XCTAssertEqual(calc().longestStreak(records), 4)
        XCTAssertEqual(calc().activeDays(records).count, 7)
    }

    func testHelpers() {
        XCTAssertEqual(StatsCalculator.share(1, of: 4), 0.25)
        XCTAssertEqual(StatsCalculator.share(1, of: 0), 0)
        XCTAssertEqual(StatsCalculator.durationText(3_900), "1 h 5 min")
        XCTAssertEqual(StatsCalculator.durationText(120), "2 min")
    }
}

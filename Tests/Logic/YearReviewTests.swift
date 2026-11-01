import XCTest
@testable import Era

final class YearReviewTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func play(_ title: String, _ artist: String = "A", _ when: Date, seconds: Double = 60) -> PlayRecord {
        PlayRecord(date: when, seconds: seconds, title: title, artist: artist)
    }

    func testAvailableYearsAreDistinctAndNewestFirst() {
        let records = [play("a", date(2024, 5, 1)), play("b", date(2026, 1, 1)), play("c", date(2026, 3, 1)), play("d", date(2025, 7, 1))]
        XCTAssertEqual(YearReview.availableYears(records, calendar: calendar), [2026, 2025, 2024])
        XCTAssertEqual(YearReview.availableYears([], calendar: calendar), [])
    }

    func testReviewOnlyCountsTheRequestedYear() {
        let records = [
            play("a", date(2025, 12, 31), seconds: 100),
            play("a", date(2026, 1, 1), seconds: 50),
            play("b", date(2026, 1, 1, 22), seconds: 70),
            play("b", date(2026, 2, 3), seconds: 80),
        ]
        let review = YearReview.make(year: 2026, from: records, calendar: calendar)
        XCTAssertEqual(review.plays, 3)
        XCTAssertEqual(review.seconds, 200)
        XCTAssertEqual(review.activeDays, 2)
        XCTAssertEqual(review.topTracks.first?.title, "b")
        XCTAssertFalse(review.isEmpty)
        XCTAssertTrue(YearReview.make(year: 2023, from: records, calendar: calendar).isEmpty)
    }

    func testNewTracksAreThoseFirstHeardThatYear() {
        let records = [
            play("old", date(2025, 6, 1)),
            play("old", date(2026, 6, 1)),
            play("fresh", date(2026, 6, 2)),
            play("fresh", date(2026, 6, 3)),
            play("other", "B", date(2026, 7, 1)),
        ]
        XCTAssertEqual(YearReview.make(year: 2026, from: records, calendar: calendar).newTracks, 2)
        XCTAssertEqual(YearReview.make(year: 2025, from: records, calendar: calendar).newTracks, 1)
    }

    func testBusiestMonthTiesGoToTheEarlierMonth() {
        let records = [play("a", date(2026, 3, 1)), play("a", date(2026, 3, 2)), play("b", date(2026, 5, 1)), play("b", date(2026, 5, 2)), play("c", date(2026, 8, 1))]
        let review = YearReview.make(year: 2026, from: records, calendar: calendar)
        XCTAssertEqual(review.busiestMonth?.month, date(2026, 3, 1, 0))
        XCTAssertEqual(review.busiestMonth?.plays, 2)
    }

    func testLongestStreak() {
        let days = [date(2026, 4, 1), date(2026, 4, 2), date(2026, 4, 3), date(2026, 4, 10), date(2026, 4, 11)]
        XCTAssertEqual(YearReview.longestStreak(days.map { play("x", $0) }, calendar: calendar), 3)
        XCTAssertEqual(YearReview.longestStreak([], calendar: calendar), 0)
        XCTAssertEqual(YearReview.longestStreak([play("x", date(2026, 4, 1)), play("y", date(2026, 4, 1, 20))], calendar: calendar), 1)
    }

    func testPeakHourAndWeekday() {
        // 2026-10-26 ist ein Montag.
        calendar.firstWeekday = 2
        let records = [play("a", date(2026, 10, 26, 21)), play("b", date(2026, 10, 26, 21)), play("c", date(2026, 10, 27, 8))]
        let review = YearReview.make(year: 2026, from: records, calendar: calendar)
        XCTAssertEqual(review.peakHour, 21)
        XCTAssertEqual(review.busiestWeekdayIndex, 0)
    }
}

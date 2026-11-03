import XCTest
@testable import Era

final class YearComparisonTests: XCTestCase {
    private func review(_ year: Int, plays: Int, seconds: Double, days: Int = 1, new: Int = 0) -> YearReview {
        YearReview(year: year, plays: plays, seconds: seconds, activeDays: days, longestStreak: 1, newTracks: new,
                   topTracks: [], topArtists: [], busiestMonth: nil, peakHour: nil, busiestWeekdayIndex: nil)
    }

    func testDeltasAndPercent() {
        let c = YearComparison.make(current: review(2026, plays: 150, seconds: 6000, days: 40, new: 10),
                                    previous: review(2025, plays: 100, seconds: 4000, days: 50, new: 4))
        XCTAssertEqual(c?.previousYear, 2025)
        XCTAssertEqual(c?.playsDelta, 50)
        XCTAssertEqual(c?.secondsDelta, 2000)
        XCTAssertEqual(c?.activeDaysDelta, -10)
        XCTAssertEqual(c?.newTracksDelta, 6)
        XCTAssertEqual(c?.secondsPercent, 50)
    }

    func testNoComparisonWithoutPreviousPlays() {
        XCTAssertNil(YearComparison.make(current: review(2026, plays: 5, seconds: 100), previous: review(2025, plays: 0, seconds: 0)))
    }

    func testNoComparisonWithLaterOrEqualYear() {
        XCTAssertNil(YearComparison.make(current: review(2025, plays: 5, seconds: 100), previous: review(2026, plays: 5, seconds: 100)))
        XCTAssertNil(YearComparison.make(current: review(2025, plays: 5, seconds: 100), previous: review(2025, plays: 5, seconds: 100)))
    }

    func testPercentIsNilWhenPreviousHadNoTime() {
        let c = YearComparison.make(current: review(2026, plays: 5, seconds: 100), previous: review(2025, plays: 3, seconds: 0))
        XCTAssertNil(c?.secondsPercent)
    }

    func testSignedFormatting() {
        XCTAssertEqual(YearComparison.signed(0), "0")
        XCTAssertEqual(YearComparison.signed(7), "+7")
        XCTAssertEqual(YearComparison.signed(-7), "\u{2212}7")
        XCTAssertEqual(YearComparison.signedPercent(-12), "\u{2212}12 %")
    }
}

import XCTest
@testable import Era

final class StatsCalculatorTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private var now: Date!

    override func setUp() {
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = date(2026, 10, 29, 12)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func play(_ title: String, _ artist: String = "A", on day: Date, seconds: Double = 60) -> PlayRecord {
        PlayRecord(date: day, seconds: seconds, title: title, artist: artist)
    }

    func testMonthBucketsAreNewestFirstAndSumSeconds() {
        let records = [play("x", on: date(2026, 9, 3), seconds: 30), play("y", on: date(2026, 10, 1)), play("z", on: date(2026, 9, 20), seconds: 70)]
        let buckets = StatsCalculator.monthBuckets(records, calendar: calendar)
        XCTAssertEqual(buckets.map(\.plays), [1, 2])
        XCTAssertEqual(buckets.last?.seconds, 100)
    }

    func testMonthlySeriesFillsEmptyMonthsOldestFirst() {
        let series = StatsCalculator.monthlySeries([play("x", on: date(2026, 8, 5))], months: 4, now: now, calendar: calendar)
        XCTAssertEqual(series.map(\.plays), [0, 1, 0, 0])
        XCTAssertEqual(series.first?.month, date(2026, 7, 1, 0))
        XCTAssertEqual(series.last?.month, date(2026, 10, 1, 0))
    }

    func testRecordsInMonthExcludesNeighbours() {
        let records = [play("a", on: date(2026, 9, 30, 23)), play("b", on: date(2026, 10, 1, 0)), play("c", on: date(2026, 11, 1, 0))]
        XCTAssertEqual(StatsCalculator.records(records, inMonthOf: now, calendar: calendar).map(\.title), ["b"])
    }

    func testTopTracksSeparatesSameTitleByArtistAndBreaksTiesAlphabetically() {
        let day = date(2026, 10, 2)
        let records = [play("Intro", "A", on: day), play("Intro", "B", on: day), play("Intro", "B", on: day), play("Zed", "A", on: day), play("Alpha", "A", on: day)]
        let top = StatsCalculator.topTracks(records, limit: 3)
        XCTAssertEqual(top.map(\.artist), ["B", "A", "A"])
        XCTAssertEqual(top.map(\.title), ["Intro", "Alpha", "Intro"])
        XCTAssertEqual(Set(top.map(\.id)).count, 3, "Same title by different artists must have distinct ids")
    }

    func testTopArtistsRespectsLimit() {
        let day = date(2026, 10, 2)
        let records = [play("1", "B", on: day), play("2", "B", on: day), play("3", "A", on: day), play("4", "C", on: day)]
        XCTAssertEqual(StatsCalculator.topArtists(records, limit: 2).map(\.name), ["B", "A"])
    }

    func testStreakCountsConsecutiveDaysAndSurvivesUntilTomorrow() {
        let records = [play("a", on: date(2026, 10, 29)), play("b", on: date(2026, 10, 28)), play("c", on: date(2026, 10, 28, 20)), play("d", on: date(2026, 10, 26))]
        XCTAssertEqual(StatsCalculator.currentStreak(records, now: now, calendar: calendar), 2)
        XCTAssertEqual(StatsCalculator.currentStreak(records, now: date(2026, 10, 30), calendar: calendar), 2, "Yesterday's play keeps the streak alive")
        XCTAssertEqual(StatsCalculator.currentStreak(records, now: date(2026, 11, 2), calendar: calendar), 0)
        XCTAssertEqual(StatsCalculator.activeDays(records, calendar: calendar), 3)
    }

    func testPeriodFiltering() {
        let records = [play("old", on: date(2025, 12, 31)), play("jan", on: date(2026, 1, 1, 0)), play("now", on: date(2026, 10, 2)), play("next", on: date(2027, 1, 1, 0))]
        XCTAssertEqual(StatsCalculator.records(records, in: .month, now: now, calendar: calendar).map(\.title), ["now"])
        XCTAssertEqual(StatsCalculator.records(records, in: .year, now: now, calendar: calendar).map(\.title), ["jan", "now"])
        XCTAssertEqual(StatsCalculator.records(records, in: .allTime, now: now, calendar: calendar).count, 4)
    }

    func testHourAndWeekdayDistributionAndPeak() {
        // 2026-10-29 is a Thursday; firstWeekday 2 = Monday -> index 3
        calendar.firstWeekday = 2
        let records = [
            play("a", on: date(2026, 10, 29, 22)), play("b", on: date(2026, 10, 29, 22)),
            play("c", on: date(2026, 10, 26, 8)),
        ]
        let hours = StatsCalculator.hourDistribution(records, calendar: calendar)
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours[22], 2)
        XCTAssertEqual(hours[8], 1)
        XCTAssertEqual(StatsCalculator.peakHour(records, calendar: calendar), 22)
        let days = StatsCalculator.weekdayDistribution(records, calendar: calendar)
        XCTAssertEqual(days[3], 2)
        XCTAssertEqual(days[0], 1)
        XCTAssertNil(StatsCalculator.peakHour([], calendar: calendar))
    }

    func testAverageSecondsPerActiveDay() {
        let records = [
            play("a", on: date(2026, 10, 29, 9), seconds: 100), play("b", on: date(2026, 10, 29, 18), seconds: 200),
            play("c", on: date(2026, 10, 28, 9), seconds: 300),
        ]
        XCTAssertEqual(StatsCalculator.averageSecondsPerActiveDay(records, calendar: calendar), 300, accuracy: 0.001)
        XCTAssertEqual(StatsCalculator.averageSecondsPerActiveDay([], calendar: calendar), 0)
    }
}

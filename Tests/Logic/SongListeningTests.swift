import XCTest
@testable import Era

final class SongListeningTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func play(_ when: Date, seconds: Double = 100) -> PlayRecord {
        PlayRecord(date: when, seconds: seconds, title: "T", artist: "A")
    }

    func testEmptyHistory() {
        let result = SongListening.make(from: [], now: date(2026, 5, 10), calendar: calendar)
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(result.firstPlayed)
        XCTAssertEqual(result.monthlyPlays, [Int](repeating: 0, count: 12))
        XCTAssertEqual(result.averageSeconds, 0)
    }

    func testTotalsAndFirstLast() {
        let events = [play(date(2026, 5, 9), seconds: 60), play(date(2026, 1, 2), seconds: 120), play(date(2026, 5, 1), seconds: 180)]
        let result = SongListening.make(from: events, now: date(2026, 5, 10), calendar: calendar)
        XCTAssertEqual(result.plays, 3)
        XCTAssertEqual(result.totalSeconds, 360)
        XCTAssertEqual(result.averageSeconds, 120)
        XCTAssertEqual(result.firstPlayed, date(2026, 1, 2))
        XCTAssertEqual(result.lastPlayed, date(2026, 5, 9))
    }

    func testMonthlyBucketsEndWithCurrentMonth() {
        let events = [play(date(2026, 5, 9)), play(date(2026, 5, 1)), play(date(2026, 4, 30)), play(date(2025, 6, 15)), play(date(2025, 5, 31))]
        let result = SongListening.make(from: events, now: date(2026, 5, 10), calendar: calendar)
        XCTAssertEqual(result.monthlyPlays.count, 12)
        XCTAssertEqual(result.monthlyPlays.last, 2)
        XCTAssertEqual(result.monthlyPlays[10], 1)
        XCTAssertEqual(result.monthlyPlays.first, 1)  // Juni 2025 ist der aelteste Bucket
        XCTAssertEqual(result.plays, 5)               // Gesamtzahl zaehlt auch aeltere Wiedergaben
    }

    func testFutureEventsAreIgnored() {
        let result = SongListening.make(from: [play(date(2026, 6, 1))], now: date(2026, 5, 10), calendar: calendar)
        XCTAssertTrue(result.isEmpty)
    }
}

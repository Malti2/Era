import Foundation
import XCTest
@testable import Era

// Montag als Wochenstart, damit die Kalenderwochen deterministisch sind.
private func mondayCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

final class ListeningGoalTests: XCTestCase {
    private let calendar = mondayCalendar()
    /// Montag, 2026-11-16 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_830_400)

    private func record(daysAgo: Double, seconds: Double) -> PlayRecord {
        PlayRecord(date: now.addingTimeInterval(-daysAgo * 86_400), seconds: seconds, title: "T", artist: "A")
    }

    func testDisabledGoalHasNoProgress() {
        let goal = ListeningGoal.make(minutesPerWeek: 0, from: [record(daysAgo: 1, seconds: 3600)], now: now, calendar: calendar)
        XCTAssertFalse(goal.isEnabled)
        XCTAssertFalse(goal.reached)
        XCTAssertEqual(goal.progress, 0)
        XCTAssertEqual(goal.streak, 0)
    }

    func testProgressAndRemaining() {
        let goal = ListeningGoal.make(minutesPerWeek: 120, from: [record(daysAgo: 0, seconds: 1800)], now: now, calendar: calendar)
        XCTAssertEqual(goal.secondsThisWeek, 1800)
        XCTAssertEqual(goal.progress, 0.25, accuracy: 0.001)
        XCTAssertEqual(goal.remainingSeconds, 5400)
        XCTAssertFalse(goal.reached)
    }

    func testReachedCapsProgressAtOne() {
        let goal = ListeningGoal.make(minutesPerWeek: 60, from: [record(daysAgo: 0, seconds: 7200)], now: now, calendar: calendar)
        XCTAssertTrue(goal.reached)
        XCTAssertEqual(goal.progress, 1)
        XCTAssertEqual(goal.remainingSeconds, 0)
    }

    func testOnlyCurrentWeekCounts() {
        // 8 Tage her = Vorwoche, darf nicht in diese Woche zaehlen.
        let goal = ListeningGoal.make(minutesPerWeek: 60, from: [record(daysAgo: 8, seconds: 3600)], now: now, calendar: calendar)
        XCTAssertEqual(goal.secondsThisWeek, 0)
        XCTAssertFalse(goal.reached)
    }

    func testStreakCountsConsecutiveReachedWeeks() {
        // Diese Woche erreicht, die zwei davor auch, die davor nicht.
        let records = [
            record(daysAgo: 0, seconds: 3600),
            record(daysAgo: 7, seconds: 3600),
            record(daysAgo: 14, seconds: 3600),
            record(daysAgo: 21, seconds: 600),
        ]
        XCTAssertEqual(ListeningGoal.streak(minutesPerWeek: 60, from: records, now: now, calendar: calendar), 3)
    }

    func testStreakStartsAtPreviousWeekWhenCurrentNotReached() {
        // Diese Woche erst 10 Minuten, die zwei Wochen davor erreicht.
        let records = [
            record(daysAgo: 0, seconds: 600),
            record(daysAgo: 7, seconds: 3600),
            record(daysAgo: 14, seconds: 3600),
            record(daysAgo: 21, seconds: 600),
        ]
        XCTAssertEqual(ListeningGoal.streak(minutesPerWeek: 60, from: records, now: now, calendar: calendar), 2)
    }

    func testStreakIsZeroWithoutAnyReachedWeek() {
        let records = [record(daysAgo: 0, seconds: 600), record(daysAgo: 7, seconds: 600)]
        XCTAssertEqual(ListeningGoal.streak(minutesPerWeek: 60, from: records, now: now, calendar: calendar), 0)
    }

    func testMakeIncludesStreak() {
        let records = [record(daysAgo: 0, seconds: 3600), record(daysAgo: 7, seconds: 3600)]
        let goal = ListeningGoal.make(minutesPerWeek: 60, from: records, now: now, calendar: calendar)
        XCTAssertTrue(goal.reached)
        XCTAssertEqual(goal.streak, 2)
    }
}

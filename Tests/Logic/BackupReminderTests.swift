import XCTest
@testable import Era

final class BackupReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    func testSmallLibrariesAreNeverNagged() {
        XCTAssertFalse(BackupReminder.isDue(songCount: 9, lastBackup: nil, libraryStarted: daysAgo(400), snoozedUntil: nil, now: now))
    }

    func testRecentBackupSuppressesReminder() {
        XCTAssertFalse(BackupReminder.isDue(songCount: 50, lastBackup: daysAgo(5), libraryStarted: daysAgo(400), snoozedUntil: nil, now: now))
    }

    func testOldBackupTriggersReminder() {
        XCTAssertTrue(BackupReminder.isDue(songCount: 50, lastBackup: daysAgo(31), libraryStarted: daysAgo(400), snoozedUntil: nil, now: now))
    }

    func testNeverBackedUpUsesLibraryAge() {
        XCTAssertFalse(BackupReminder.isDue(songCount: 20, lastBackup: nil, libraryStarted: daysAgo(10), snoozedUntil: nil, now: now))
        XCTAssertTrue(BackupReminder.isDue(songCount: 20, lastBackup: nil, libraryStarted: daysAgo(45), snoozedUntil: nil, now: now))
        XCTAssertFalse(BackupReminder.isDue(songCount: 20, lastBackup: nil, libraryStarted: nil, snoozedUntil: nil, now: now))
    }

    func testSnoozeHidesUntilItExpires() {
        let snoozed = BackupReminder.snoozeDate(from: now)
        XCTAssertFalse(BackupReminder.isDue(songCount: 50, lastBackup: daysAgo(90), libraryStarted: nil, snoozedUntil: snoozed, now: now))
        let later = now.addingTimeInterval(15 * 86_400)
        XCTAssertTrue(BackupReminder.isDue(songCount: 50, lastBackup: daysAgo(90), libraryStarted: nil, snoozedUntil: snoozed, now: later))
    }

    func testDaysSince() {
        XCTAssertEqual(BackupReminder.daysSince(daysAgo(3.5), now: now), 3)
        XCTAssertNil(BackupReminder.daysSince(nil, now: now))
        XCTAssertEqual(BackupReminder.daysSince(now.addingTimeInterval(100), now: now), 0)
    }
}

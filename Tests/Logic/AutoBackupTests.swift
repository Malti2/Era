import XCTest
@testable import Era

final class AutoBackupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFileNameRoundtrips() throws {
        let name = AutoBackup.fileName(for: now)
        XCTAssertTrue(name.hasPrefix("Era-Auto-") && name.hasSuffix(".json"))
        XCTAssertEqual(try XCTUnwrap(AutoBackup.date(fromFileName: name)).timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.5)
    }

    func testKnownTimestamp() {
        XCTAssertEqual(AutoBackup.fileName(for: Date(timeIntervalSince1970: 0)), "Era-Auto-19700101-000000.json")
    }

    func testForeignNamesAreRejected() {
        for name in ["Era-Backup-2026.json", "Era-Auto-xxxx-yy.json", "Era-Auto-20260101-1200.json", "notes.txt", "Era-Auto-20260101-120000.txt"] {
            XCTAssertNil(AutoBackup.date(fromFileName: name), name)
        }
    }

    func testDueOnlyForFilledLibrariesAndAfterInterval() {
        XCTAssertFalse(AutoBackup.isDue(songCount: 0, lastBackup: nil, now: now))
        XCTAssertTrue(AutoBackup.isDue(songCount: 3, lastBackup: nil, now: now))
        XCTAssertFalse(AutoBackup.isDue(songCount: 3, lastBackup: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(AutoBackup.isDue(songCount: 3, lastBackup: now.addingTimeInterval(-21 * 3600), now: now))
    }

    func testPruningKeepsNewestAndIgnoresForeignFiles() {
        let names = (0..<8).map { AutoBackup.fileName(for: now.addingTimeInterval(Double($0) * 86_400)) } + ["readme.txt"]
        let doomed = AutoBackup.namesToPrune(names, keep: 5)
        XCTAssertEqual(doomed.count, 3)
        XCTAssertEqual(Set(doomed), Set(names.prefix(3)))
        XCTAssertEqual(AutoBackup.sorted(names).first, names[7])
    }

    func testPruningNeverDeletesEverything() {
        let names = [AutoBackup.fileName(for: now)]
        XCTAssertTrue(AutoBackup.namesToPrune(names, keep: 0).isEmpty)
    }
}

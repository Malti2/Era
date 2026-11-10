import XCTest
@testable import Era

final class VersionSwitchTests: XCTestCase {
    func testSimilarLengthsKeepAbsoluteTime() {
        XCTAssertEqual(VersionSwitch.position(time: 60, from: 200, to: 210), 60, accuracy: 0.001)
    }

    func testVeryDifferentLengthsKeepRelativeProgress() {
        XCTAssertEqual(VersionSwitch.position(time: 100, from: 200, to: 400), 200, accuracy: 0.001)
    }

    func testStartStaysAtStart() {
        XCTAssertEqual(VersionSwitch.position(time: 0, from: 200, to: 210), 0)
    }

    func testPositionIsClampedBeforeTheEnd() {
        XCTAssertEqual(VersionSwitch.position(time: 199, from: 200, to: 180), 179, accuracy: 0.001)
    }

    func testUnknownOldDurationFallsBackToAbsoluteTime() {
        XCTAssertEqual(VersionSwitch.position(time: 30, from: 0, to: 120), 30, accuracy: 0.001)
    }

    func testInvalidNewDurationGivesZero() {
        XCTAssertEqual(VersionSwitch.position(time: 30, from: 100, to: 0), 0)
    }

    func testPairLabel() {
        XCTAssertEqual(VersionSwitch.pairLabel("Demo", "Final"), "Demo ⇄ Final")
    }
}

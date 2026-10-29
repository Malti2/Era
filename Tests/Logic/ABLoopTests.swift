import XCTest
@testable import Era

final class ABLoopTests: XCTestCase {
    func testButtonCyclesOffToStartToActiveToOff() {
        var loop = ABLoop()
        XCTAssertEqual(loop.stage, .off)
        XCTAssertTrue(loop.advance(at: 10, duration: 200))
        XCTAssertEqual(loop.stage, .startSet)
        XCTAssertTrue(loop.advance(at: 40, duration: 200))
        XCTAssertEqual(loop.stage, .active)
        XCTAssertEqual(loop.start, 10)
        XCTAssertEqual(loop.end, 40)
        XCTAssertTrue(loop.advance(at: 50, duration: 200))
        XCTAssertEqual(loop.stage, .off)
    }

    func testEndTooCloseToStartIsRefusedAndKeepsStart() {
        var loop = ABLoop()
        loop.advance(at: 10, duration: 200)
        XCTAssertFalse(loop.advance(at: 10.5, duration: 200))
        XCTAssertFalse(loop.advance(at: 5, duration: 200), "B before A is refused")
        XCTAssertEqual(loop.stage, .startSet)
        XCTAssertEqual(loop.start, 10)
    }

    func testEndIsClampedBeforeTrackEnd() {
        var loop = ABLoop()
        loop.advance(at: 100, duration: 120)
        loop.advance(at: 120, duration: 120)
        XCTAssertEqual(loop.end ?? 0, 119.7, accuracy: 0.001)
    }

    func testJumpsBackOnlyWhenPlaybackReachesTheEnd() {
        var loop = ABLoop()
        loop.advance(at: 10, duration: 200)
        loop.advance(at: 40, duration: 200)
        XCTAssertNil(loop.jumpTarget(for: 39.9))
        XCTAssertEqual(loop.jumpTarget(for: 40.1), 10)
        XCTAssertNil(loop.jumpTarget(for: 90), "A deliberate seek far past B is left alone")
    }

    func testInactiveLoopNeverJumps() {
        var loop = ABLoop()
        XCTAssertNil(loop.jumpTarget(for: 50))
        loop.advance(at: 10, duration: 200)
        XCTAssertNil(loop.jumpTarget(for: 50))
    }
}

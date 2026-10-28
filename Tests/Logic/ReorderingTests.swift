import XCTest
@testable import Era

final class ReorderingTests: XCTestCase {
    private let base = ["a", "b", "c", "d", "e"]

    func testMoveDownPlacesBeforeDestinationIndex() {
        XCTAssertEqual(Reordering.move(base, from: [0], to: 3), ["b", "c", "a", "d", "e"])
    }

    func testMoveUp() {
        XCTAssertEqual(Reordering.move(base, from: [3], to: 1), ["a", "d", "b", "c", "e"])
    }

    func testMoveToEnd() {
        XCTAssertEqual(Reordering.move(base, from: [1], to: 5), ["a", "c", "d", "e", "b"])
    }

    func testMoveMultipleKeepsTheirOrder() {
        XCTAssertEqual(Reordering.move(base, from: [0, 2], to: 5), ["b", "d", "e", "a", "c"])
        XCTAssertEqual(Reordering.move(base, from: [1, 3], to: 0), ["b", "d", "a", "c", "e"])
    }

    func testMoveOntoOwnPositionIsNoOp() {
        XCTAssertEqual(Reordering.move(base, from: [2], to: 2), base)
        XCTAssertEqual(Reordering.move(base, from: [2], to: 3), base)
    }

    func testInvalidIndicesAreIgnored() {
        XCTAssertEqual(Reordering.move(base, from: [9], to: 0), base)
        XCTAssertEqual(Reordering.move(base, from: [0], to: 99), ["b", "c", "d", "e", "a"])
    }
}

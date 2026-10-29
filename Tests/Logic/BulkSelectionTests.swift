import XCTest
@testable import Era

final class BulkSelectionTests: XCTestCase {
    func testToggleSelectAllAndClear() {
        let a = UUID(), b = UUID(), c = UUID()
        var selection = BulkSelection()
        selection.toggle(a)
        XCTAssertTrue(selection.contains(a))
        selection.toggle(a)
        XCTAssertTrue(selection.isEmpty)

        selection.selectAll([a, b])
        selection.selectAll([b, c])
        XCTAssertEqual(selection.count, 3)
        XCTAssertTrue(selection.coversAll(of: [a, b, c]))
        selection.clear()
        XCTAssertFalse(selection.coversAll(of: [a]))
    }

    func testCoversAllIsFalseForEmptyList() {
        XCTAssertFalse(BulkSelection().coversAll(of: []))
    }

    func testPruneRemovesDeletedSongs() {
        let kept = UUID(), gone = UUID()
        var selection = BulkSelection()
        selection.selectAll([kept, gone])
        selection.prune(to: [kept])
        XCTAssertEqual(selection.ids, [kept])
    }

    func testTagCoverage() {
        let songs = [["Demo", "Sketch"], ["demo"], []]
        XCTAssertEqual(BulkTagging.coverage(of: "DEMO", in: songs), .some)
        XCTAssertEqual(BulkTagging.coverage(of: "Sketch", in: [["sketch"]]), .all)
        XCTAssertEqual(BulkTagging.coverage(of: "x", in: songs), .none)
        XCTAssertEqual(BulkTagging.coverage(of: "x", in: []), .none)
    }

    func testTappingPartialTagAddsToEveryone() {
        XCTAssertTrue(BulkTagging.shouldAdd(.none))
        XCTAssertTrue(BulkTagging.shouldAdd(.some))
        XCTAssertFalse(BulkTagging.shouldAdd(.all))
    }

    func testCleanNameCollapsesWhitespace() {
        XCTAssertEqual(BulkTagging.cleanName("  late   night \n"), "late night")
        XCTAssertNil(BulkTagging.cleanName("  \t "))
    }

    func testRenameResolution() {
        let existing = ["Demo", "Live", "Sketch"]
        XCTAssertEqual(TagRename.resolve("  ", current: "Demo", existing: existing), .invalid)
        XCTAssertEqual(TagRename.resolve("Demo ", current: "Demo", existing: existing), .unchanged)
        XCTAssertEqual(TagRename.resolve("live", current: "Demo", existing: existing), .merge(into: "Live"))
        XCTAssertEqual(TagRename.resolve("Rough", current: "Demo", existing: existing), .rename(to: "Rough"))
        XCTAssertEqual(TagRename.resolve("demo", current: "Demo", existing: existing), .rename(to: "demo"), "Changing only the case is a plain rename")
    }
}

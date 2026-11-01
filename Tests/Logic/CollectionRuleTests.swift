import XCTest
@testable import Era

final class CollectionRuleTests: XCTestCase {
    func testEmptyRuleIsEmpty() {
        XCTAssertTrue(CollectionRule().isEmpty)
        var rule = CollectionRule()
        rule.toggle(status: "Demo")
        XCTAssertFalse(rule.isEmpty)
        rule.toggle(status: "Demo")
        XCTAssertTrue(rule.isEmpty)
    }

    func testSongMustHaveAllTagsAndStatuses() {
        let a = UUID(), b = UUID(), c = UUID()
        var rule = CollectionRule()
        rule.toggle(tag: a)
        rule.toggle(tag: b)
        rule.toggle(status: "Demo")

        XCTAssertTrue(rule.matches(tagIDs: [a, b, c], statuses: ["Demo", "Live"]))
        XCTAssertFalse(rule.matches(tagIDs: [a], statuses: ["Demo"]))
        XCTAssertFalse(rule.matches(tagIDs: [a, b], statuses: ["Live"]))
    }

    func testTagOnlyRuleIgnoresStatuses() {
        let a = UUID()
        var rule = CollectionRule()
        rule.toggle(tag: a)
        XCTAssertTrue(rule.matches(tagIDs: [a], statuses: []))
    }

    func testNameValidation() {
        XCTAssertEqual(CollectionName.validate("   ", existing: []), .empty)
        XCTAssertEqual(CollectionName.validate("  Road Trip ", existing: ["Gym"]), .ok("Road Trip"))
        XCTAssertEqual(CollectionName.validate("gym", existing: ["Gym"]), .duplicate)
    }

    func testRenamingKeepsOwnNameButCannotTakeAnothers() {
        XCTAssertEqual(CollectionName.validate("gym", existing: ["Gym", "Focus"], editing: "Gym"), .ok("gym"))
        XCTAssertEqual(CollectionName.validate("Focus", existing: ["Gym", "Focus"], editing: "Gym"), .duplicate)
    }
}

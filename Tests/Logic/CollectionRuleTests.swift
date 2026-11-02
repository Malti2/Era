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

    func testExcludedTagsAndStatusesRejectSongs() {
        let a = UUID(), skip = UUID()
        var rule = CollectionRule(tagIDs: [a])
        rule.cycle(tag: skip); rule.cycle(tag: skip) // include -> exclude
        rule.cycle(status: "Leak"); rule.cycle(status: "Leak")
        XCTAssertEqual(rule.mark(tag: skip), .exclude)
        XCTAssertTrue(rule.matches(tagIDs: [a], statuses: ["Demo"]))
        XCTAssertFalse(rule.matches(tagIDs: [a, skip], statuses: []))
        XCTAssertFalse(rule.matches(tagIDs: [a], statuses: ["Leak"]))
    }

    func testOnlyExclusionsMeansEverythingExceptThose() {
        let bad = UUID()
        var rule = CollectionRule()
        rule.cycle(tag: bad); rule.cycle(tag: bad)
        XCTAssertFalse(rule.isEmpty)
        XCTAssertEqual(rule.includeCount, 0)
        XCTAssertTrue(rule.matches(tagIDs: [], statuses: []))
        XCTAssertTrue(rule.matches(tagIDs: [UUID()], statuses: ["Demo"]))
        XCTAssertFalse(rule.matches(tagIDs: [bad], statuses: []))
    }

    func testMatchAnyNeedsOnlyOneIncludedCondition() {
        let a = UUID(), b = UUID()
        var rule = CollectionRule(tagIDs: [a, b], statusNames: ["Live"], matchAny: true)
        XCTAssertTrue(rule.needsMatchMode)
        XCTAssertTrue(rule.matches(tagIDs: [b], statuses: []))
        XCTAssertTrue(rule.matches(tagIDs: [], statuses: ["Live"]))
        XCTAssertFalse(rule.matches(tagIDs: [UUID()], statuses: ["Demo"]))
        rule.matchAny = false
        XCTAssertFalse(rule.matches(tagIDs: [b], statuses: []))
    }

    func testCycleWalksIncludeExcludeNone() {
        let id = UUID()
        var rule = CollectionRule()
        XCTAssertEqual(rule.mark(tag: id), .none)
        rule.cycle(tag: id); XCTAssertEqual(rule.mark(tag: id), .include)
        rule.cycle(tag: id); XCTAssertEqual(rule.mark(tag: id), .exclude)
        rule.cycle(tag: id); XCTAssertEqual(rule.mark(tag: id), .none)
        XCTAssertTrue(rule.isEmpty)
        rule.cycle(status: "Demo"); XCTAssertEqual(rule.mark(status: "Demo"), .include)
        rule.cycle(status: "Demo"); XCTAssertEqual(rule.mark(status: "Demo"), .exclude)
    }

    func testToggleReplacesExclusion() {
        let id = UUID()
        var rule = CollectionRule(excludedTagIDs: [id])
        rule.toggle(tag: id)
        XCTAssertEqual(rule.mark(tag: id), .include)
        XCTAssertTrue(rule.excludedTagIDs.isEmpty)
    }

    func testPrunedDropsUnknownTags() {
        let keep = UUID(), gone = UUID()
        let rule = CollectionRule(tagIDs: [keep, gone], excludedTagIDs: [gone])
        XCTAssertEqual(rule.pruned(toExistingTagIDs: [keep]), CollectionRule(tagIDs: [keep]))
    }

    func testLabelsListStatusBeforeTagsAndSkipUnknownTags() {
        let night = UUID(), gone = UUID(), skip = UUID()
        let names = [night: "Night", skip: "Skit"]
        let rule = CollectionRule(tagIDs: [night, gone], statusNames: ["Demo"], excludedTagIDs: [skip], excludedStatusNames: ["Leak"])
        let labels = rule.labels(tagName: { names[$0] })
        XCTAssertEqual(labels.include, ["Demo", "Night"])
        XCTAssertEqual(labels.exclude, ["Leak", "Skit"])
    }
}

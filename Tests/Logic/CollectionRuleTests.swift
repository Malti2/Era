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

    // MARK: gespeicherte Suche

    func testQueryOnlyRuleIsNotEmptyButBlankQueryIs() {
        XCTAssertFalse(CollectionRule(query: "era:synth").isEmpty)
        XCTAssertTrue(CollectionRule(query: "   ").isEmpty)
        XCTAssertNil(CollectionRule(query: "  ").parsedQuery)
    }

    func testQueryNarrowsTagAndStatusMatches() {
        let tag = UUID()
        let rule = CollectionRule(tagIDs: [tag], query: "plays:0 -era:pop")
        let fresh = SearchableSong(title: "Fresh", era: "Synth", playCount: 0)
        let heard = SearchableSong(title: "Heard", era: "Synth", playCount: 3)
        let pop = SearchableSong(title: "Pop", era: "Pop", playCount: 0)
        XCTAssertTrue(rule.matches(tagIDs: [tag], statuses: [], searchable: { fresh }))
        XCTAssertFalse(rule.matches(tagIDs: [tag], statuses: [], searchable: { heard }))
        XCTAssertFalse(rule.matches(tagIDs: [tag], statuses: [], searchable: { pop }))
        XCTAssertFalse(rule.matches(tagIDs: [], statuses: [], searchable: { fresh }), "tags still required")
    }

    func testQueryOnlyRuleWithExclusionMeansEverythingExceptThat() {
        let rule = CollectionRule(query: "-demo")
        XCTAssertTrue(rule.matches(tagIDs: [], statuses: [], searchable: { SearchableSong(title: "Finished") }))
        XCTAssertFalse(rule.matches(tagIDs: [], statuses: [], searchable: { SearchableSong(title: "Demo Take") }))
    }

    func testSearchableIsOnlyBuiltWhenAQueryIsSet() {
        var built = 0
        _ = CollectionRule(statusNames: ["Demo"]).matches(tagIDs: [], statuses: ["Demo"], searchable: { built += 1; return SearchableSong(title: "x") })
        XCTAssertEqual(built, 0)
    }
}

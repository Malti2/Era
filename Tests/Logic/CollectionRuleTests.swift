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

    // MARK: Regel-Gruppen

    func testGroupIsAndedWithMainRule() {
        let a = UUID(), b = UUID(), c = UUID()
        // Hauptregel: A dabei; Gruppe: B oder C.
        let rule = CollectionRule(tagIDs: [a], groups: [CollectionRule(tagIDs: [b, c], matchAny: true)])
        XCTAssertTrue(rule.matches(tagIDs: [a, b], statuses: []))
        XCTAssertTrue(rule.matches(tagIDs: [a, c], statuses: []))
        XCTAssertFalse(rule.matches(tagIDs: [a], statuses: []))
        XCTAssertFalse(rule.matches(tagIDs: [b, c], statuses: []))
    }

    func testGroupExclusionsReject() {
        let a = UUID(), skip = UUID()
        let rule = CollectionRule(tagIDs: [a], groups: [CollectionRule(excludedTagIDs: [skip])])
        XCTAssertTrue(rule.matches(tagIDs: [a], statuses: []))
        XCTAssertFalse(rule.matches(tagIDs: [a, skip], statuses: []))
    }

    func testGroupWithAllModeNeedsEveryCondition() {
        let a = UUID(), b = UUID()
        let rule = CollectionRule(groups: [CollectionRule(tagIDs: [a], statusNames: ["Live"])])
        XCTAssertTrue(rule.matches(tagIDs: [a, b], statuses: ["Live"]))
        XCTAssertFalse(rule.matches(tagIDs: [a], statuses: []))
        XCTAssertFalse(rule.isEmpty, "groups alone define a collection")
    }

    func testEmptyGroupChangesNothing() {
        let a = UUID()
        let rule = CollectionRule(tagIDs: [a], groups: [CollectionRule()])
        XCTAssertTrue(rule.matches(tagIDs: [a], statuses: []))
        XCTAssertTrue(CollectionRule(groups: [CollectionRule()]).isEmpty)
    }

    func testGroupsJSONRoundTrip() {
        let a = UUID(), b = UUID()
        let rule = CollectionRule(tagIDs: [a], groups: [CollectionRule(tagIDs: [b], excludedStatusNames: ["Leak"], matchAny: true)])
        let json = CollectionRule.encodeGroups(rule.groups)
        XCTAssertFalse(json.isEmpty)
        XCTAssertEqual(CollectionRule.decodeGroups(json), rule.groups)
        XCTAssertEqual(CollectionRule.encodeGroups([]), "")
        XCTAssertEqual(CollectionRule.decodeGroups(""), [])
        XCTAssertEqual(CollectionRule.decodeGroups("kein json"), [])
    }

    func testNormalizedDropsEmptyGroupsAndNestedContent() {
        let inner = CollectionRule(tagIDs: [UUID()], query: "plays:0", groups: [CollectionRule(tagIDs: [UUID()])])
        let rule = CollectionRule(groups: [CollectionRule(), inner]).normalized()
        XCTAssertEqual(rule.groups.count, 1)
        XCTAssertEqual(rule.groups[0].groups, [])
        XCTAssertEqual(rule.groups[0].query, "")
    }

    func testPrunedDropsUnknownTagsInGroups() {
        let keep = UUID(), gone = UUID()
        let rule = CollectionRule(groups: [CollectionRule(tagIDs: [keep, gone], excludedTagIDs: [gone])])
        XCTAssertEqual(rule.pruned(toExistingTagIDs: [keep]).groups, [CollectionRule(tagIDs: [keep])])
    }

    func testRemappingTagsCoversGroupsAndIncludeWins() {
        let old = UUID(), new = UUID(), other = UUID()
        let rule = CollectionRule(tagIDs: [old], groups: [CollectionRule(tagIDs: [other], excludedTagIDs: [old])])
        let mapped = rule.remappingTags { $0 == old ? new : $0 }
        XCTAssertEqual(mapped.tagIDs, [new])
        XCTAssertEqual(mapped.groups[0].excludedTagIDs, [new], "Ausschluss in der Gruppe folgt dem Mapping")
        // Faellt ein Tag nach dem Mapping in beiden Listen, gewinnt "dabei".
        let clash = CollectionRule(tagIDs: [new], excludedTagIDs: [old])
        XCTAssertEqual(clash.remappingTags { $0 == old ? new : $0 }.excludedTagIDs, [])
        XCTAssertEqual(rule.remappingTags { _ in nil }.allTagIDs, [])
    }

    func testAllTagIDsIncludesGroups() {
        let a = UUID(), b = UUID(), c = UUID()
        let rule = CollectionRule(tagIDs: [a], excludedTagIDs: [b], groups: [CollectionRule(tagIDs: [c])])
        XCTAssertEqual(rule.allTagIDs, [a, b, c])
    }

    func testGroupLabels() {
        let night = UUID(), gone = UUID()
        let names = [night: "Night"]
        let rule = CollectionRule(groups: [CollectionRule(tagIDs: [night, gone], statusNames: ["Demo"], excludedStatusNames: ["Leak"], matchAny: true)])
        let labels = rule.groupLabels(tagName: { names[$0] })
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels[0].include, ["Demo", "Night"])
        XCTAssertEqual(labels[0].exclude, ["Leak"])
        XCTAssertTrue(labels[0].matchAny)
    }

    func testQueryWithDuplicatesOperator() {
        let rule = CollectionRule(query: "duplicates:yes")
        let dup = SearchableSong(title: "Same", isDuplicate: true)
        let single = SearchableSong(title: "Other")
        XCTAssertTrue(rule.matches(tagIDs: [], statuses: [], searchable: { dup }))
        XCTAssertFalse(rule.matches(tagIDs: [], statuses: [], searchable: { single }))
        let notDup = CollectionRule(query: "duplicates:no")
        XCTAssertFalse(notDup.matches(tagIDs: [], statuses: [], searchable: { dup }))
        XCTAssertTrue(notDup.matches(tagIDs: [], statuses: [], searchable: { single }))
    }
}

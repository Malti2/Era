import XCTest
import SwiftData
@testable import Era

@MainActor
final class CollectionStoreTests: XCTestCase {
    private var store: EraStore!

    override func setUp() async throws {
        store = EraStore(context: ModelContext(Persistence.makeContainer(inMemory: true)))
        store.ensureStatusTags()
    }

    private func rule(tags: [Tag] = [], statuses: [String] = []) -> CollectionRule {
        CollectionRule(tagIDs: Set(tags.map(\.id)), statusNames: Set(statuses))
    }

    func testCreateTrimsNameAndStoresRule() throws {
        let tag = store.makeTag(named: "Night")
        let pack = try XCTUnwrap(store.createCollection(named: "  Late  ", rule: rule(tags: [tag], statuses: ["Demo"])))
        XCTAssertEqual(pack.name, "Late")
        XCTAssertTrue(pack.confirmed)
        XCTAssertEqual(pack.rule, rule(tags: [tag], statuses: ["Demo"]))
        XCTAssertEqual(try store.allPacks().count, 1)
    }

    func testCreateRejectsEmptyRuleBlankAndDuplicateNames() {
        let tag = store.makeTag(named: "Night")
        XCTAssertNil(store.createCollection(named: "Empty rule", rule: CollectionRule()))
        XCTAssertNil(store.createCollection(named: "  ", rule: rule(tags: [tag])))
        XCTAssertNotNil(store.createCollection(named: "Late", rule: rule(tags: [tag])))
        XCTAssertNil(store.createCollection(named: "late", rule: rule(tags: [tag])))
        XCTAssertEqual((try? store.allPacks().count) ?? 0, 1)
    }

    func testUpdateRenamesAndConfirmsSuggestion() throws {
        let night = store.makeTag(named: "Night"), day = store.makeTag(named: "Day")
        let suggestion = Pack(name: "Night", tagIDs: [night.id], confirmed: false)
        store.insertPack(suggestion)
        XCTAssertTrue(store.updateCollection(suggestion, name: "Evening", rule: rule(tags: [night, day])))
        XCTAssertEqual(suggestion.name, "Evening")
        XCTAssertEqual(Set(suggestion.tagIDs), [night.id, day.id])
        XCTAssertTrue(suggestion.confirmed)
    }

    func testUpdateKeepsOwnNameButRefusesOthersAndEmptyRules() throws {
        let tag = store.makeTag(named: "Night")
        let first = try XCTUnwrap(store.createCollection(named: "One", rule: rule(tags: [tag])))
        _ = try XCTUnwrap(store.createCollection(named: "Two", rule: rule(statuses: ["Live"])))

        XCTAssertTrue(store.updateCollection(first, name: "one", rule: rule(tags: [tag])))
        XCTAssertFalse(store.updateCollection(first, name: "Two", rule: rule(tags: [tag])))
        XCTAssertFalse(store.updateCollection(first, name: "One", rule: CollectionRule()))
        XCTAssertEqual(first.name, "one")
    }

    func testSongMatchesCollectionRule() throws {
        let tag = store.makeTag(named: "Night")
        let demo = try XCTUnwrap(store.tag(named: "Demo"))
        let song = Song(title: "S")
        song.tags = [tag, demo]
        store.insertSong(song)
        XCTAssertTrue(song.matches(rule(tags: [tag], statuses: ["Demo"])))
        XCTAssertFalse(song.matches(rule(tags: [tag], statuses: ["Live"])))
    }
}

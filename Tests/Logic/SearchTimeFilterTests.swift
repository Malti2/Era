import XCTest
@testable import Era

final class SearchTimeFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15
    private let day = 86_400.0

    private func song(_ title: String, added: Double? = nil, played: Double? = nil, length: Double = 0) -> SearchableSong {
        SearchableSong(title: title, dateAdded: added.map { now.addingTimeInterval(-$0 * day) },
                       lastPlayedAt: played.map { now.addingTimeInterval(-$0 * day) }, duration: length)
    }

    private func titles(_ query: String, _ songs: [SearchableSong]) -> [String] {
        let byID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0.title) })
        return SongSearch.search(query, in: songs, now: now).map { byID[$0.id] ?? "?" }.sorted()
    }

    func testDateConditionParsing() {
        XCTAssertEqual(DateCondition("7d"), .within(days: 7))
        XCTAssertEqual(DateCondition("<2w"), .within(days: 14))
        XCTAssertEqual(DateCondition(">3m"), .olderThan(days: 90))
        XCTAssertEqual(DateCondition(">=1y"), .olderThan(days: 365))
        XCTAssertEqual(DateCondition("2024"), .years(2024...2024))
        XCTAssertEqual(DateCondition("2025-2022"), .years(2022...2025))
        XCTAssertNil(DateCondition("soon"))
        XCTAssertNil(DateCondition(">2024"))
        XCTAssertNil(DateCondition("12"))
        XCTAssertNil(DateCondition(""))
    }

    func testAddedWithinAndOlder() {
        let songs = [song("new", added: 3), song("mid", added: 40), song("old", added: 400), song("unknown")]
        XCTAssertEqual(titles("added:7d", songs), ["new"])
        XCTAssertEqual(titles("added:2m", songs), ["mid", "new"])
        XCTAssertEqual(titles("added:>1y", songs), ["old"])
        XCTAssertEqual(titles("-added:30d fav", songs), [], "exclusion plus a filter that nothing meets")
    }

    func testPlayedIgnoresNeverPlayedSongs() {
        let songs = [song("recent", played: 2), song("stale", played: 200), song("never")]
        XCTAssertEqual(titles("played:7d", songs), ["recent"])
        XCTAssertEqual(titles("played:>90d", songs), ["stale"])
        XCTAssertEqual(titles("unplayed", songs.map { var s = $0; s.playCount = $0.lastPlayedAt == nil ? 0 : 3; return s }), ["never"])
    }

    func testAddedYearUsesCalendarYear() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let year = cal.component(.year, from: now.addingTimeInterval(-3 * day))
        XCTAssertEqual(titles("added:\(year)", [song("this", added: 3), song("ancient", added: 3_000)]), ["this"])
    }

    func testLengthComparisons() {
        let songs = [song("snippet", length: 25), song("single", length: 200), song("epic", length: 540), song("noduration")]
        XCTAssertEqual(titles("length:<1m", songs), ["snippet"])
        XCTAssertEqual(titles("length:>5m", songs), ["epic"])
        XCTAssertEqual(titles("length:2m-4m", songs), ["single"])
        XCTAssertEqual(titles("len:<=200s", songs), ["single", "snippet"])
        XCTAssertEqual(titles("length:>2.5m", songs), ["epic", "single"])
        XCTAssertNil(DurationComparison("fast"))
        XCTAssertNil(DurationComparison("5m"), "a bare length is not a comparison")
    }

    func testFiltersCombineWithTermsAndCompletion() {
        let songs = [song("Neon Rain", added: 2, length: 100), song("Neon Dust", added: 90, length: 100)]
        XCTAssertEqual(titles("neon added:7d", songs), ["Neon Rain"])
        let completion = SearchCompletion.make(for: "added:", songs: songs).map(\.query)
        XCTAssertTrue(completion.contains("added:7d"))
        XCTAssertEqual(SearchCompletion.make(for: "len", songs: songs).map(\.query), ["length:"])
    }
}

final class SearchHelpTests: XCTestCase {
    func testEveryFilterExampleIsUnderstoodByTheParser() {
        for entry in SearchHelp.allEntries {
            let query = SongSearchQuery(entry.example)
            XCTAssertFalse(query.isEmpty, entry.example)
            if entry.isFilter {
                XCTAssertFalse(query.filters.isEmpty, "\(entry.example) should parse into a filter")
            } else {
                XCTAssertTrue(!query.terms.isEmpty || !query.excludedTerms.isEmpty, entry.example)
            }
        }
    }

    func testExamplesAreUniqueAndGrouped() {
        let examples = SearchHelp.allEntries.map(\.example)
        XCTAssertEqual(Set(examples).count, examples.count)
        XCTAssertGreaterThanOrEqual(SearchHelp.groups.count, 4)
        XCTAssertTrue(SearchHelp.groups.allSatisfy { !$0.entries.isEmpty })
    }
}

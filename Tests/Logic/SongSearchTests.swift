import XCTest
@testable import Era

final class SongSearchTests: XCTestCase {
    private let songs: [SearchableSong] = [
        SearchableSong(title: "Café del Mar", artist: "Energy 52", album: "Sunset", year: 1997, tags: ["chill"], statuses: ["Released"], versionNames: ["OG", "Remaster"]),
        SearchableSong(title: "Night Drive", artist: "Neon", album: "Late Night", era: "Synth Era", year: 2019, tags: ["late night", "synth"], statuses: ["Unreleased"], versionNames: ["Demo"], isFavorite: true),
        SearchableSong(title: "Drive", artist: "Neon", year: 2020, tags: ["synth"], statuses: ["Leak"], versionNames: ["OG"], playCount: 4),
        SearchableSong(title: "Blue Hour", artist: "Aurora Lane", album: "Hours", year: 2021, statuses: ["Demo"]),
    ]

    private func titles(_ raw: String) -> [String] {
        SongSearch.search(raw, in: songs).compactMap { hit in songs.first { $0.id == hit.id }?.title }
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertTrue(SongSearch.search("   ", in: songs).isEmpty)
    }

    func testIgnoresCaseAndAccents() {
        XCTAssertEqual(titles("CAFE"), ["Café del Mar"])
        XCTAssertEqual(titles("café"), ["Café del Mar"])
    }

    func testAllTermsMustMatchInAnyOrder() {
        XCTAssertEqual(titles("neon night"), ["Night Drive"])
        XCTAssertEqual(titles("night neon"), ["Night Drive"])
        XCTAssertTrue(titles("neon sunset").isEmpty)
    }

    func testTitleMatchesRankAboveOtherFields() {
        // "drive": exakter Titel vor Prefix-Titel
        XCTAssertEqual(titles("drive"), ["Drive", "Night Drive"])
    }

    func testFiltersNarrowResults() {
        XCTAssertEqual(Set(titles("tag:synth")), ["Night Drive", "Drive"])
        XCTAssertEqual(titles("status:leak"), ["Drive"])
        XCTAssertEqual(titles("status:un"), ["Night Drive"])
        XCTAssertEqual(titles("fav"), ["Night Drive"])
        XCTAssertEqual(titles("version:remaster"), ["Café del Mar"])
    }

    func testYearFilterSupportsSingleYearAndRange() {
        XCTAssertEqual(titles("year:1997"), ["Café del Mar"])
        XCTAssertEqual(Set(titles("year:2019-2020")), ["Night Drive", "Drive"])
        XCTAssertEqual(Set(titles("year:2020-2019")), ["Night Drive", "Drive"], "reversed ranges are normalised")
    }

    func testFilterAndTermCombine() {
        XCTAssertEqual(titles("tag:synth night"), ["Night Drive"])
    }

    func testQuotedPhrasesStayTogether() {
        let query = SongSearchQuery("\"blue hour\" tag:\"late night\"")
        XCTAssertEqual(query.terms, ["blue hour"])
        XCTAssertEqual(query.filters, [.tag("late night")])
        XCTAssertEqual(titles("tag:\"late night\""), ["Night Drive"])
    }

    func testUnknownOperatorFallsBackToPlainTerm() {
        let query = SongSearchQuery("foo:bar")
        XCTAssertEqual(query.terms, ["foo:bar"])
        XCTAssertTrue(query.filters.isEmpty)
    }

    func testMatchedFieldsReportWhereItHit() throws {
        let hit = try XCTUnwrap(SongSearch.search("synth", in: songs).first { $0.id == songs[1].id })
        XCTAssertTrue(hit.matchedFields.contains(.tag))
        XCTAssertTrue(hit.matchedFields.contains(.era))
        XCTAssertFalse(hit.matchedFields.contains(.title))
    }

    func testPlayCountBreaksScoreTies() {
        let a = SearchableSong(title: "Echo A", playCount: 1), b = SearchableSong(title: "Echo B", playCount: 9)
        let hits = SongSearch.search("echo", in: [a, b])
        XCTAssertEqual(hits.map(\.id), [b.id, a.id])
    }

    func testSuggestionsListMostCommonStatusesAndTags() {
        let suggestions = SearchSuggestions.make(from: songs)
        XCTAssertTrue(suggestions.contains(SearchSuggestion(query: "tag:synth", label: "#synth", count: 2)))
        XCTAssertTrue(suggestions.contains { $0.query == "tag:\"late night\"" })
        XCTAssertTrue(suggestions.contains { $0.query == "status:Leak" })
        XCTAssertLessThanOrEqual(suggestions.count, 8)
        XCTAssertEqual(suggestions.first?.count, 1)
    }

    func testRecentSearchesDedupeLimitAndIgnoreTiny() {
        var recents = RecentSearches.adding("Neon", to: [])
        recents = RecentSearches.adding("drive", to: recents)
        recents = RecentSearches.adding("NEON", to: recents)
        XCTAssertEqual(recents, ["NEON", "drive"])
        XCTAssertEqual(RecentSearches.adding("a", to: recents), recents)
        var many: [String] = []
        for i in 0..<20 { many = RecentSearches.adding("query \(i)", to: many) }
        XCTAssertEqual(many.count, RecentSearches.limit)
        XCTAssertEqual(many.first, "query 19")
    }

    func testNotesAndMarkerLabelsAreFindableButRankLow() {
        let withNote = SearchableSong(title: "Untitled 4", notes: "Gitarrenriff im Intro, Vocals noch roh")
        let withMarker = SearchableSong(title: "Sketch", markerLabels: ["Beat Drop"])
        let titled = SearchableSong(title: "Riff Raff")
        let hits = SongSearch.search("riff", in: [withNote, withMarker, titled])
        XCTAssertEqual(hits.map(\.id), [titled.id, withNote.id])
        XCTAssertTrue(hits[1].matchedFields.contains(.note))
        XCTAssertEqual(SongSearch.search("drop", in: [withNote, withMarker]).map(\.id), [withMarker.id])
    }
}

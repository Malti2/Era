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

    // MARK: Search v2: Ausschluesse, Zusatzfilter, Vervollstaendigung

    private let extra: [SearchableSong] = [
        SearchableSong(title: "Sketch One", artist: "Neon", era: "Synth Era", tags: ["demo"], statuses: ["Demo"], versionNames: ["OG"], playCount: 0, notes: "Riff aus dem Proberaum"),
        SearchableSong(title: "Sketch Two", artist: "Neon", era: "Pop Era", tags: ["demo", "synth"], statuses: ["Demo"], versionNames: ["OG", "v2", "v3"], playCount: 9, markerLabels: ["Hook"]),
        SearchableSong(title: "Finished", artist: "Aurora Lane", era: "Pop Era", statuses: ["Released"], versionNames: ["OG"], isFavorite: true, playCount: 2),
    ]

    private func extraTitles(_ raw: String) -> [String] {
        SongSearch.search(raw, in: extra).compactMap { hit in extra.first { $0.id == hit.id }?.title }.sorted()
    }

    func testMinusExcludesTermsAndFilters() {
        XCTAssertEqual(extraTitles("sketch -two"), ["Sketch One"])
        XCTAssertEqual(extraTitles("neon -tag:synth"), ["Sketch One"])
        XCTAssertEqual(extraTitles("status:demo -fav"), ["Sketch One", "Sketch Two"])
        XCTAssertEqual(extraTitles("pop -is:unplayed"), ["Finished", "Sketch Two"])
    }

    func testOnlyExclusionsFindNothing() {
        XCTAssertTrue(extraTitles("-demo").isEmpty)
        XCTAssertEqual(SongSearchQuery("-demo").excludedTerms, ["demo"])
    }

    func testHasNotesMarkersAndUnplayed() {
        XCTAssertEqual(extraTitles("has:notes"), ["Sketch One"])
        XCTAssertEqual(extraTitles("has:markers"), ["Sketch Two"])
        XCTAssertEqual(extraTitles("unplayed"), ["Sketch One"])
        XCTAssertEqual(extraTitles("is:unplayed"), ["Sketch One"])
        XCTAssertEqual(extraTitles("neon -has:notes"), ["Sketch Two"])
    }

    func testCountComparisons() {
        XCTAssertEqual(extraTitles("plays:>1"), ["Finished", "Sketch Two"])
        XCTAssertEqual(extraTitles("plays:<=2"), ["Finished", "Sketch One"])
        XCTAssertEqual(extraTitles("plays:0"), ["Sketch One"])
        XCTAssertEqual(extraTitles("versions:>=3"), ["Sketch Two"])
        XCTAssertEqual(extraTitles("versions:1 neon"), ["Sketch One"])
        XCTAssertNil(CountComparison("abc"))
        XCTAssertNil(CountComparison(">"))
        XCTAssertEqual(CountComparison(">=4"), CountComparison(op: .atLeast, value: 4))
    }

    func testEraFilter() {
        XCTAssertEqual(extraTitles("era:pop"), ["Finished", "Sketch Two"])
        XCTAssertEqual(extraTitles("era:\"synth era\""), ["Sketch One"])
    }

    func testUnknownOperatorStaysATerm() {
        let query = SongSearchQuery("has:wings")
        XCTAssertTrue(query.filters.isEmpty)
        XCTAssertEqual(query.terms, ["has:wings"])
    }

    func testCompletionSuggestsOperators() {
        XCTAssertEqual(SearchCompletion.make(for: "ta", songs: extra).map(\.query), ["tag:"])
        XCTAssertEqual(SearchCompletion.make(for: "neon ver", songs: extra).map(\.query), ["neon version:", "neon versions:"])
        XCTAssertTrue(SearchCompletion.make(for: "t", songs: extra).isEmpty, "one letter is too noisy")
        XCTAssertTrue(SearchCompletion.make(for: "tag:", songs: extra).isEmpty == false)
        XCTAssertTrue(SearchCompletion.make(for: "neon ", songs: extra).isEmpty)
    }

    func testCompletionSuggestsLibraryValues() {
        XCTAssertEqual(SearchCompletion.make(for: "tag:s", songs: extra).map(\.query), ["tag:synth"])
        XCTAssertEqual(SearchCompletion.make(for: "-tag:d", songs: extra).map(\.query), ["-tag:demo"])
        XCTAssertEqual(SearchCompletion.make(for: "era:", songs: extra).map(\.query), ["era:\"Pop Era\"", "era:\"Synth Era\""])
        XCTAssertEqual(SearchCompletion.make(for: "has:", songs: extra).map(\.query), ["has:notes", "has:markers"])
        XCTAssertTrue(SearchCompletion.make(for: "tag:synth", songs: extra).isEmpty, "already complete")
        XCTAssertTrue(SearchCompletion.make(for: "tag:\"late n", songs: extra).isEmpty, "open quote = phrase in progress")
    }
}

final class TrackSearchTests: XCTestCase {
    func testTrackOperatorFiltersByTrackNumber() {
        let first = SearchableSong(title: "One", trackNumber: 1)
        let third = SearchableSong(title: "Three", trackNumber: 3)
        let loose = SearchableSong(title: "Loose")
        let songs = [first, third, loose]
        func titles(_ query: String) -> [String] {
            let ids = Set(SongSearch.search(query, in: songs).map(\.id))
            return songs.filter { ids.contains($0.id) }.map(\.title)
        }
        XCTAssertEqual(titles("track:0"), ["Loose"])
        XCTAssertEqual(titles("track:>=2"), ["Three"])
        XCTAssertEqual(titles("-track:0").sorted(), ["One", "Three"])
    }
}

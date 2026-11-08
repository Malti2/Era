import XCTest
@testable import Era

final class SongRatingTests: XCTestCase {
    func testClampStaysWithinZeroToFive() {
        XCTAssertEqual(SongRating.clamp(-3), 0)
        XCTAssertEqual(SongRating.clamp(3), 3)
        XCTAssertEqual(SongRating.clamp(99), 5)
    }

    func testTappingTheCurrentStarClearsIt() {
        XCTAssertEqual(SongRating.toggled(current: 0, tapped: 4), 4)
        XCTAssertEqual(SongRating.toggled(current: 4, tapped: 4), 0)
        XCTAssertEqual(SongRating.toggled(current: 4, tapped: 2), 2)
    }

    func testAdjustStopsAtTheEnds() {
        XCTAssertEqual(SongRating.adjusted(5, by: 1), 5)
        XCTAssertEqual(SongRating.adjusted(0, by: -1), 0)
        XCTAssertEqual(SongRating.adjusted(2, by: 1), 3)
    }

    func testStarsText() {
        XCTAssertEqual(SongRating.stars(3), "★★★☆☆")
        XCTAssertEqual(SongRating.stars(0), "☆☆☆☆☆")
    }

    func testSearchOperatorFiltersByRating() {
        let songs = [
            SearchableSong(title: "Five", rating: 5), SearchableSong(title: "Four", rating: 4),
            SearchableSong(title: "Two", rating: 2), SearchableSong(title: "None"),
        ]
        func titles(_ query: String) -> Set<String> {
            Set(SongSearch.search(query, in: songs).compactMap { hit in songs.first { $0.id == hit.id }?.title })
        }
        XCTAssertEqual(titles("rating:>=4"), ["Five", "Four"])
        XCTAssertEqual(titles("rating:5"), ["Five"])
        XCTAssertEqual(titles("rating:0"), ["None"])
        XCTAssertEqual(titles("stars:<3 -rating:0"), ["Two"])
    }

    func testTopRatedFilterAttribute() {
        let filter = LibraryFilter(attributes: [.topRated])
        XCTAssertTrue(filter.matches(SearchableSong(title: "A", rating: 4)))
        XCTAssertFalse(filter.matches(SearchableSong(title: "B", rating: 3)))
        XCTAssertFalse(filter.matches(SearchableSong(title: "C")))
    }

    func testRatingSortPutsBestFirstAndUnratedLast() {
        let rows = [SortRow(title: "B", rating: 0), SortRow(title: "A", rating: 3), SortRow(title: "C", rating: 5), SortRow(title: "D", rating: 3)]
        let order = LibrarySort.rating.ordered(rows)
        XCTAssertEqual(order.map { id in rows.first { $0.id == id }!.title }, ["C", "A", "D", "B"])
    }

    func testRatingSurvivesBackupAndOldBackupsDecode() throws {
        var entry = LibraryBackup.SongEntry(id: UUID(), title: "A", artist: "", album: "", era: "", year: nil, dateAdded: Date(timeIntervalSince1970: 0),
                                            playCount: 0, lastPlayedAt: nil, isFavorite: false, resumePosition: 0, primaryVersionID: nil, tagIDs: [])
        XCTAssertNil(entry.rating)
        entry.rating = 4
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let backup = LibraryBackup(songs: [entry], versions: [], tags: [], packs: [], playlists: [])
        XCTAssertEqual(try LibraryBackup.decode(from: encoder.encode(backup)).songs.first?.rating, 4)
    }
}

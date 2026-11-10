import XCTest
@testable import Era

final class LibraryFilterTests: XCTestCase {
    private let a = SearchableSong(title: "A", tags: ["Sketch", "Night"], statuses: ["Demo"], isFavorite: true)
    private let b = SearchableSong(title: "B", tags: ["sketch"], statuses: ["Leak"])
    private let c = SearchableSong(title: "C", statuses: ["Demo", "Live"], isFavorite: true)

    func testInactiveFilterKeepsEverythingInOrder() {
        let filter = LibraryFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.ids(in: [c, a, b]), [c.id, a.id, b.id])
    }

    func testFavoritesOnly() {
        var filter = LibraryFilter()
        filter.favoritesOnly = true
        XCTAssertEqual(filter.ids(in: [a, b, c]), [a.id, c.id])
    }

    func testStatusesAreOr() {
        var filter = LibraryFilter()
        filter.toggle(status: "Leak")
        filter.toggle(status: "Live")
        XCTAssertEqual(filter.ids(in: [a, b, c]), [b.id, c.id])
    }

    func testTagsAreAndAndIgnoreCase() {
        var filter = LibraryFilter()
        filter.toggle(tag: "SKETCH")
        XCTAssertEqual(filter.ids(in: [a, b, c]), [a.id, b.id])
        filter.toggle(tag: "night")
        XCTAssertEqual(filter.ids(in: [a, b, c]), [a.id])
    }

    func testCombinedAndToggleOff() {
        var filter = LibraryFilter()
        filter.favoritesOnly = true
        filter.toggle(status: "Demo")
        filter.toggle(tag: "Sketch")
        XCTAssertEqual(filter.activeCount, 3)
        XCTAssertEqual(filter.ids(in: [a, b, c]), [a.id])
        filter.toggle(tag: "Sketch")
        XCTAssertEqual(filter.ids(in: [a, b, c]), [a.id, c.id])
    }
}

final class LibraryFilterAttributeTests: XCTestCase {
    private let heard = SearchableSong(title: "Heard", versionNames: ["OG"], playCount: 3)
    private let fresh = SearchableSong(title: "Fresh", versionNames: ["OG", "Demo"], playCount: 0, notes: "Refrain neu")
    private let blank = SearchableSong(title: "Blank", versionNames: ["OG"], playCount: 0, notes: "  \n ")

    func testNotPlayed() {
        var filter = LibraryFilter()
        filter.toggle(.notPlayed)
        XCTAssertEqual(filter.ids(in: [heard, fresh, blank]), [fresh.id, blank.id])
    }

    func testNotesIgnoreWhitespaceOnlyText() {
        var filter = LibraryFilter()
        filter.toggle(.hasNotes)
        XCTAssertEqual(filter.ids(in: [heard, fresh, blank]), [fresh.id])
    }

    func testAttributesCombineWithAnd() {
        var filter = LibraryFilter()
        filter.toggle(.multipleVersions)
        filter.toggle(.notPlayed)
        XCTAssertEqual(filter.ids(in: [heard, fresh, blank]), [fresh.id])
        XCTAssertEqual(filter.activeCount, 2)
        filter.toggle(.notPlayed)
        filter.toggle(.multipleVersions)
        XCTAssertFalse(filter.isActive)
    }

    func testAttributesSurviveEncodingAndOldFiltersStillDecode() {
        var filter = LibraryFilter()
        filter.toggle(.hasNotes)
        XCTAssertEqual(LibraryFilter.decode(filter.encoded), filter)
        let legacy = LibraryFilter.decode(#"{"favoritesOnly":true,"statuses":["Demo"],"tags":[]}"#)
        XCTAssertTrue(legacy.favoritesOnly)
        XCTAssertEqual(legacy.statuses, ["Demo"])
        XCTAssertTrue(legacy.attributes.isEmpty)
    }

    func testUnknownAttributeFromNewerVersionIsDropped() {
        let decoded = LibraryFilter.decode(#"{"favoritesOnly":false,"statuses":[],"tags":[],"attributes":["somethingNew"]}"#)
        XCTAssertFalse(decoded.isActive)
    }
}

final class LibraryFilterPersistenceTests: XCTestCase {
    func testEncodedFilterRoundtrips() {
        var filter = LibraryFilter()
        filter.favoritesOnly = true
        filter.toggle(status: "Demo")
        filter.toggle(tag: "Night")
        XCTAssertEqual(LibraryFilter.decode(filter.encoded), filter)
    }

    func testInactiveFilterEncodesToEmptyString() {
        XCTAssertEqual(LibraryFilter().encoded, "")
        XCTAssertEqual(LibraryFilter.decode(""), LibraryFilter())
    }

    func testGarbageDecodesToNoFilter() {
        XCTAssertEqual(LibraryFilter.decode("{broken"), LibraryFilter())
    }

    func testUnratedMatchesOnlySongsWithoutStars() {
        let rated = SearchableSong(title: "Rated", rating: 3)
        let none = SearchableSong(title: "None", rating: 0)
        var filter = LibraryFilter()
        filter.toggle(.unrated)
        XCTAssertEqual(filter.ids(in: [rated, none]), [none.id])
    }

    func testUnratedAndTopRatedExcludeEachOther() {
        let top = SearchableSong(title: "Top", rating: 5)
        let none = SearchableSong(title: "None", rating: 0)
        var filter = LibraryFilter()
        filter.toggle(.unrated)
        filter.toggle(.topRated)
        XCTAssertTrue(filter.ids(in: [top, none]).isEmpty)
    }
}

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

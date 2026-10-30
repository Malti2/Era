import XCTest
@testable import Era

final class PlaylistToolsTests: XCTestCase {
    private func row(_ title: String, _ artist: String = "", added: Double = 0, duration: Double = 0) -> PlaylistRow {
        PlaylistRow(title: title, artist: artist, dateAdded: Date(timeIntervalSince1970: added), duration: duration)
    }

    private func titles(_ order: PlaylistSortOrder, _ rows: [PlaylistRow]) -> [String] {
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.title) })
        return order.ordered(rows).compactMap { byID[$0] }
    }

    func testTitleSortIsNaturalAndCaseInsensitive() {
        let rows = [row("Track 10"), row("track 2"), row("beta"), row("Alpha")]
        XCTAssertEqual(titles(.title, rows), ["Alpha", "beta", "track 2", "Track 10"])
    }

    func testArtistSortPutsMissingArtistsLast() {
        let rows = [row("1", ""), row("2", "Zed"), row("3", "Abe")]
        XCTAssertEqual(titles(.artist, rows), ["3", "2", "1"])
    }

    func testNewestAndLongestFirstWithStableTies() {
        let rows = [row("old", added: 1, duration: 100), row("new", added: 9, duration: 100), row("mid", added: 5, duration: 300)]
        XCTAssertEqual(titles(.newest, rows), ["new", "mid", "old"])
        XCTAssertEqual(titles(.longest, rows), ["mid", "old", "new"])
    }

    func testReverse() {
        XCTAssertEqual(titles(.reverse, [row("a"), row("b"), row("c")]), ["c", "b", "a"])
    }

    func testTextExportNumbersTracksAndSkipsEmptyParts() {
        let text = PlaylistTextExport.text(header: "Night (2 tracks)", items: [
            .init(title: "One", artist: "A", duration: 201),
            .init(title: "Two", artist: "", duration: 0),
        ])
        XCTAssertEqual(text, "Night (2 tracks)\n\n1. One – A (3:21)\n2. Two")
    }
}

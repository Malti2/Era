import XCTest
@testable import Era

final class LibraryOrderingTests: XCTestCase {
    private func row(_ title: String, artist: String = "", year: Int? = nil, plays: Int = 0, added: Double = 0, duration: Double = 0) -> SortRow {
        SortRow(title: title, artist: artist, year: year, playCount: plays, dateAdded: Date(timeIntervalSince1970: added), duration: duration)
    }

    private func titles(_ sort: LibrarySort, _ rows: [SortRow]) -> [String] {
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.title) })
        return sort.ordered(rows).compactMap { byID[$0] }
    }

    func testRecentPutsNewestFirst() {
        XCTAssertEqual(titles(.recent, [row("Old", added: 1), row("New", added: 9), row("Mid", added: 5)]), ["New", "Mid", "Old"])
    }

    func testTitleUsesNaturalNumericOrderAndIgnoresCase() {
        XCTAssertEqual(titles(.title, [row("Track 10"), row("track 2"), row("Alpha")]), ["Alpha", "track 2", "Track 10"])
    }

    func testArtistPutsUnknownLastAndBreaksTiesByTitle() {
        let rows = [row("Z", artist: "Neon"), row("A", artist: ""), row("B", artist: "Neon"), row("C", artist: "Aurora")]
        XCTAssertEqual(titles(.artist, rows), ["C", "B", "Z", "A"])
    }

    func testYearIsNewestFirstWithUndatedLast() {
        let rows = [row("Old", year: 1999), row("None"), row("New", year: 2024), row("Same", year: 2024)]
        XCTAssertEqual(titles(.year, rows), ["New", "Same", "Old", "None"])
    }

    func testMostPlayedAndLongest() {
        let rows = [row("A", plays: 1, duration: 300), row("B", plays: 5, duration: 60), row("C", plays: 5, duration: 120)]
        XCTAssertEqual(titles(.mostPlayed, rows), ["B", "C", "A"])
        XCTAssertEqual(titles(.longest, rows), ["A", "C", "B"])
    }

    func testGroupingMergesCaseAndAccentVariantsAndSortsUnknownLast() {
        let ids = (0..<5).map { _ in UUID() }
        let groups = LibraryGrouping.groups(of: [
            (ids[0], "Zebra"), (ids[1], "cafe"), (ids[2], ""), (ids[3], "Café"), (ids[4], "Álbum 2")
        ])
        XCTAssertEqual(groups.map(\.name), ["Álbum 2", "cafe", "Zebra", ""])
        XCTAssertEqual(groups[1].ids, [ids[1], ids[3]])
    }
}

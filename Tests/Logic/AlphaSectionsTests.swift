import XCTest
@testable import Era

final class AlphaSectionsTests: XCTestCase {
    private func rows(_ titles: [String], artist: String = "") -> [SortRow] {
        titles.map { SortRow(title: $0, artist: artist) }
    }

    func testLetterFoldsAccentsAndCase() {
        XCTAssertEqual(AlphaSections.letter(for: "álbum"), "A")
        XCTAssertEqual(AlphaSections.letter(for: "  zebra"), "Z")
        XCTAssertEqual(AlphaSections.letter(for: "99 Problems"), "#")
        XCTAssertEqual(AlphaSections.letter(for: ""), "#")
        XCTAssertEqual(AlphaSections.letter(for: "¿Qué?"), "#")
    }

    func testShortListsAndNonAlphabeticSortsAreNotGrouped() {
        let few = rows(["A", "B", "C"])
        XCTAssertNil(AlphaSections.sections(orderedRows: few, sort: .title))
        let many = rows((0..<25).map { "Song \($0)" })
        XCTAssertNil(AlphaSections.sections(orderedRows: many, sort: .recent))
        XCTAssertNil(AlphaSections.sections(orderedRows: many, sort: .mostPlayed))
    }

    func testGroupsConsecutiveRowsAndKeepsOrder() throws {
        var titles = (0..<10).map { "Apple \($0)" }
        titles += (0..<8).map { "Banana \($0)" }
        titles += (0..<4).map { "42 \($0)" }
        let input = rows(titles)
        let sections = try XCTUnwrap(AlphaSections.sections(orderedRows: input, sort: .title))
        XCTAssertEqual(sections.map(\.letter), ["A", "B", "#"])
        XCTAssertEqual(sections.map(\.ids.count), [10, 8, 4])
        XCTAssertEqual(sections.flatMap(\.ids), input.map(\.id))
    }

    func testArtistSortGroupsByArtistLetter() throws {
        var input = (0..<12).map { SortRow(title: "T\($0)", artist: "Beatles") }
        input += (0..<12).map { SortRow(title: "T\($0)", artist: "") }
        let sections = try XCTUnwrap(AlphaSections.sections(orderedRows: input, sort: .artist))
        XCTAssertEqual(sections.map(\.letter), ["B", "#"])
    }
}

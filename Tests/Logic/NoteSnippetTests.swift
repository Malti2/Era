import XCTest
@testable import Era

final class NoteSnippetTests: XCTestCase {
    func testShortTextIsReturnedWhole() {
        XCTAssertEqual(NoteSnippet.excerpt(in: ["Gitarrenriff im Intro"], terms: ["riff"]), "Gitarrenriff im Intro")
    }

    func testLongTextIsCutAroundTheMatchWithEllipses() throws {
        let text = String(repeating: "alpha ", count: 20) + "Gitarrenriff" + String(repeating: " omega", count: 20)
        let snippet = try XCTUnwrap(NoteSnippet.excerpt(in: [text], terms: ["riff"], radius: 10))
        XCTAssertTrue(snippet.hasPrefix("…"))
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertTrue(snippet.contains("riff"))
        XCTAssertLessThan(snippet.count, 40)
    }

    func testMatchIgnoresCaseAndAccents() {
        XCTAssertNotNil(NoteSnippet.excerpt(in: ["Café Demo"], terms: ["cafe"]))
        XCTAssertNotNil(NoteSnippet.excerpt(in: ["BIG DROP"], terms: ["drop"]))
    }

    func testNewlinesBecomeSpaces() {
        XCTAssertEqual(NoteSnippet.excerpt(in: ["erste Zeile\nzweite Zeile"], terms: ["zweite"]), "erste Zeile zweite Zeile")
    }

    func testNoMatchOrNoTermsGivesNil() {
        XCTAssertNil(NoteSnippet.excerpt(in: ["nothing here"], terms: ["riff"]))
        XCTAssertNil(NoteSnippet.excerpt(in: ["text"], terms: []))
        XCTAssertNil(NoteSnippet.excerpt(in: [], terms: ["x"]))
    }

    func testFirstMatchingCandidateWins() {
        XCTAssertEqual(NoteSnippet.excerpt(in: ["no", "Beat Drop", "drop again"], terms: ["drop"]), "Beat Drop")
    }
}

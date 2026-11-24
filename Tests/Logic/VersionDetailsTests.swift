import XCTest
@testable import Era

final class VersionDetailsTests: XCTestCase {
    func testYearParsing() {
        XCTAssertEqual(VersionDetails.parseYear(" 2019 "), .valid(2019))
        XCTAssertEqual(VersionDetails.parseYear(""), .empty)
        XCTAssertEqual(VersionDetails.parseYear("  "), .empty)
        XCTAssertEqual(VersionDetails.parseYear("19"), .invalid)
        XCTAssertEqual(VersionDetails.parseYear("20x1"), .invalid)
        XCTAssertEqual(VersionDetails.parseYear("9999"), .invalid)
    }

    func testOverrideIsNilWhenBlankOrSameAsSong() {
        XCTAssertNil(VersionDetails.override("", songValue: "Midnight"))
        XCTAssertNil(VersionDetails.override("  Midnight", songValue: "Midnight"))
        XCTAssertEqual(VersionDetails.override("  Midnight  (Demo) ", songValue: "Midnight"), "Midnight (Demo)")
    }

    func testYearParsingBoundaries() {
        XCTAssertEqual(VersionDetails.parseYear("1900"), .valid(1900))
        XCTAssertEqual(VersionDetails.parseYear("2200"), .valid(2200))
        XCTAssertEqual(VersionDetails.parseYear("1899"), .invalid)
        XCTAssertEqual(VersionDetails.parseYear("2201"), .invalid)
        XCTAssertEqual(VersionDetails.parseYear("2019.5"), .invalid)
        XCTAssertEqual(VersionDetails.parseYear("20x1"), .invalid)
        // Swift-Int akzeptiert Vorzeichen und fuehrende Nullen - im Editor harmlos.
        XCTAssertEqual(VersionDetails.parseYear("+2019"), .valid(2019))
        XCTAssertEqual(VersionDetails.parseYear("02019"), .valid(2019))
        XCTAssertEqual(VersionDetails.parseYear("٢٠١٩"), .invalid, "unicode digits are not parsed")
    }

    func testOverrideIgnoresWhitespaceOnlyDifferences() {
        XCTAssertNil(VersionDetails.override("Midnight   (Demo)", songValue: "Midnight (Demo)"))
        XCTAssertNil(VersionDetails.override("  Midnight (Demo)  ", songValue: "Midnight (Demo)"))
    }

    func testOverrideIsCaseSensitive() {
        XCTAssertEqual(VersionDetails.override("midnight", songValue: "Midnight"), "midnight")
    }

    func testOverrideAgainstEmptySongValue() {
        XCTAssertEqual(VersionDetails.override("Midnight", songValue: ""), "Midnight")
        XCTAssertNil(VersionDetails.override("   ", songValue: ""))
    }
}

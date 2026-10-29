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
}

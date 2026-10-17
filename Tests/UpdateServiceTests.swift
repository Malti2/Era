import XCTest
@testable import Era

final class UpdateServiceTests: XCTestCase {
    func testNumericVersionComparison() {
        XCTAssertTrue(UpdateService.isNewer("27.0.10", than: "27.0.9"))
        XCTAssertTrue(UpdateService.isNewer("28.0.0", than: "27.9.9"))
        XCTAssertFalse(UpdateService.isNewer("27.0.4", than: "27.0.4"))
        XCTAssertFalse(UpdateService.isNewer("27.0.3", than: "27.0.4"))
    }

    func testReleaseDecodingStripsTagPrefixAndBetaSuffix() throws {
        let json = """
        {"tag_name":"v27.0.4-beta.1","body":"notes","assets":[
          {"name":"Era-unsigned.ipa","browser_download_url":"https://example.com/Era-unsigned.ipa"}]}
        """
        let release = try JSONDecoder().decode(UpdateService.Release.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, "27.0.4")
        XCTAssertEqual(release.notes, "notes")
        XCTAssertEqual(release.ipaName, "Era-unsigned.ipa")
    }

    func testReleaseWithoutIPAThrows() {
        let json = #"{"tag_name":"v1.0.0","body":"","assets":[{"name":"x.dmg","browser_download_url":"https://example.com/x.dmg"}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(UpdateService.Release.self, from: Data(json.utf8)))
    }
}

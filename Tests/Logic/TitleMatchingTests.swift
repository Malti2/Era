import XCTest
@testable import Era

final class TitleMatchingTests: XCTestCase {
    private func cand(_ title: String, _ artist: String = "") -> TitleCandidate {
        TitleCandidate(id: UUID(), title: title, artist: artist)
    }

    func testParseStripsVersionSuffixes() {
        XCTAssertEqual(TitleMatching.parse("Sunrise (Demo)"), ParsedTitle(base: "Sunrise", hint: "Demo"))
        XCTAssertEqual(TitleMatching.parse("Sunrise [Live 2019]"), ParsedTitle(base: "Sunrise", hint: "Live 2019"))
        XCTAssertEqual(TitleMatching.parse("Sunrise - v2"), ParsedTitle(base: "Sunrise", hint: "v2"))
        XCTAssertEqual(TitleMatching.parse("Sunrise v3"), ParsedTitle(base: "Sunrise", hint: "v3"))
        XCTAssertEqual(TitleMatching.parse("Sunrise_OG"), ParsedTitle(base: "Sunrise", hint: "OG"))
        XCTAssertEqual(TitleMatching.parse("Sunrise (Live) - v2"), ParsedTitle(base: "Sunrise", hint: "Live v2"))
    }

    func testParseKeepsOrdinaryTitlesIntact() {
        XCTAssertEqual(TitleMatching.parse("Sunrise"), ParsedTitle(base: "Sunrise", hint: nil))
        XCTAssertEqual(TitleMatching.parse("Heaven (Is a Place)"), ParsedTitle(base: "Heaven (Is a Place)", hint: nil))
        XCTAssertEqual(TitleMatching.parse("Mr. Brightside - Part Two"), ParsedTitle(base: "Mr. Brightside - Part Two", hint: nil))
        XCTAssertEqual(TitleMatching.parse("  Spaced  "), ParsedTitle(base: "Spaced", hint: nil))
        XCTAssertEqual(TitleMatching.parse("(Demo)").hint, nil, "nothing left of the title: keep it")
    }

    func testVersionNamesMapToPresets() {
        XCTAssertEqual(TitleMatching.versionName(for: "Demo"), "Demo")
        XCTAssertEqual(TitleMatching.versionName(for: "demo take 2"), "Demo")
        XCTAssertEqual(TitleMatching.versionName(for: "v2"), "V2")
        XCTAssertEqual(TitleMatching.versionName(for: "Live 2019"), "Live")
        XCTAssertEqual(TitleMatching.versionName(for: "Remastered"), "Remaster")
        XCTAssertEqual(TitleMatching.versionName(for: "og"), "OG")
        XCTAssertEqual(TitleMatching.versionName(for: "Acoustic"), "Acoustic")
        XCTAssertNil(TitleMatching.versionName(for: nil))
        XCTAssertNil(TitleMatching.versionName(for: "  "))
    }

    func testSuggestFindsBaseTitleAndVersionName() {
        let target = cand("Sunrise", "Mira")
        let result = TitleMatching.suggest(title: "Sunrise (Demo)", artist: "Mira", in: [cand("Other"), target])
        XCTAssertEqual(result, TitleSuggestion(id: target.id, versionName: "Demo"))
    }

    func testSuggestIgnoresAccentsCaseAndPunctuation() {
        let target = cand("Café del Mar")
        XCTAssertEqual(TitleMatching.suggest(title: "cafe del mar!", artist: "", in: [target])?.id, target.id)
    }

    func testSuggestRespectsDifferentArtists() {
        XCTAssertNil(TitleMatching.suggest(title: "Sunrise", artist: "Mira", in: [cand("Sunrise", "Jonas")]))
        XCTAssertNotNil(TitleMatching.suggest(title: "Sunrise", artist: "", in: [cand("Sunrise", "Jonas")]), "unknown artist stays compatible")
    }

    func testSuggestPrefersExactBaseOverContainment() {
        let loose = cand("Sunrise Boulevard")
        let exact = cand("Sunrise v1")
        XCTAssertEqual(TitleMatching.suggest(title: "Sunrise", artist: "", in: [loose, exact])?.id, exact.id)
    }

    func testSuggestRejectsShortAndUnrelatedTitles() {
        XCTAssertNil(TitleMatching.suggest(title: "Hi", artist: "", in: [cand("Hi")]))
        XCTAssertNil(TitleMatching.suggest(title: "Moonlight", artist: "", in: [cand("Sunrise")]))
    }

    func testSimilarGroupsFindVersionsButNotExactTwins() {
        let a = cand("Sunrise", "Mira"), b = cand("Sunrise (Demo)", "Mira"), c = cand("Sunrise - v2")
        let twin1 = cand("Echo"), twin2 = cand("Echo")
        let other = cand("Sunrise", "Jonas")
        let groups = TitleMatching.similarGroups([a, b, c, twin1, twin2, other])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0]), [a.id, b.id, c.id])
    }

    func testSimilarGroupsNeedAtLeastTwoSongs() {
        XCTAssertTrue(TitleMatching.similarGroups([cand("Solo"), cand("Duo")]).isEmpty)
        XCTAssertTrue(TitleMatching.similarGroups([]).isEmpty)
    }
}

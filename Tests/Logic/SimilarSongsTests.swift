import XCTest
@testable import Era

final class SimilarSongsTests: XCTestCase {
    private func profile(_ artist: String = "", album: String = "", era: String = "", year: Int? = nil,
                         tags: [String] = [], statuses: [String] = [], favorite: Bool = false,
                         lastPlayed: Date? = nil) -> SimilarityProfile {
        SimilarityProfile(artist: artist, album: album, era: era, year: year, tags: tags, statuses: statuses,
                          isFavorite: favorite, lastPlayedAt: lastPlayed)
    }

    func testSimilarityAddsUpAndIgnoresCaseAndAccents() {
        let seed = profile("Beyoncé", album: "Lemonade", era: "2016", year: 2016, tags: ["Sketch"], statuses: ["Demo"])
        let other = profile("beyonce", album: "LEMONADE", era: "2016", year: 2017, tags: ["sketch"], statuses: ["demo"])
        // 3 artist + 2 album + 2.5 era + 1.5 tag + 0.75 status + 1 year
        XCTAssertEqual(SimilarSongs.similarity(seed, other), 10.75, accuracy: 0.0001)
        XCTAssertEqual(SimilarSongs.similarity(seed, profile("Other")), 0)
    }

    func testEmptyFieldsNeverMatch() {
        XCTAssertEqual(SimilarSongs.similarity(profile(), profile()), 0)
    }

    func testRankPrefersCloserSongsAndSkipsSeedAndExcluded() {
        let seed = profile("A", era: "2020", tags: ["x"])
        let close = profile("A", era: "2020", tags: ["x"])
        let medium = profile("B", era: "2020")
        let far = profile("C")
        let excluded = profile("A", era: "2020")
        let ids = SimilarSongs.rank(seed: seed, in: [seed, far, medium, close, excluded], excluding: [excluded.id])
        XCTAssertEqual(ids, [close.id, medium.id])
    }

    func testRankIsDeterministicForSeedAndRespectsLimit() {
        let seed = profile("A", tags: ["x"])
        let library = (0..<30).map { _ in profile("Artist\(Int.random(in: 0..<5))", tags: ["x"]) }
        let one = SimilarSongs.rank(seed: seed, in: library, limit: 10, randomSeed: 7)
        let two = SimilarSongs.rank(seed: seed, in: library, limit: 10, randomSeed: 7)
        XCTAssertEqual(one, two)
        XCTAssertEqual(one.count, 10)
    }

    func testRecentlyPlayedSongsDropBelowFreshOnes() {
        let now = Date()
        let seed = profile("A", era: "1999")
        let fresh = profile("B", era: "1999")
        let justPlayed = profile("C", era: "1999", lastPlayed: now.addingTimeInterval(-600))
        let ids = SimilarSongs.rank(seed: seed, in: [justPlayed, fresh], now: now)
        XCTAssertEqual(ids.first, fresh.id)
    }

    func testSpreadArtistsBreaksUpLongRuns() {
        let songs = [profile("A"), profile("A"), profile("A"), profile("B")]
        let spread = SimilarSongs.spreadArtists(songs).map(\.artist)
        XCTAssertEqual(spread, ["A", "A", "B", "A"])
    }

    func testNothingSimilarMeansEmptyResult() {
        XCTAssertTrue(SimilarSongs.rank(seed: profile("A"), in: [profile("B"), profile("C")]).isEmpty)
    }
}

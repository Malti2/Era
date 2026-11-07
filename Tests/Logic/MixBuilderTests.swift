import XCTest
@testable import Era

final class MixBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day = 86_400.0

    private func song(_ artist: String = "A", plays: Int = 0, last: Double? = nil, added: Double = 100, fav: Bool = false) -> MixCandidate {
        MixCandidate(id: UUID(), artist: artist, playCount: plays,
                     lastPlayedAt: last.map { now.addingTimeInterval(-$0 * day) },
                     dateAdded: now.addingTimeInterval(-added * day), isFavorite: fav)
    }

    func testSameSeedGivesSameMixAndDifferentSeedChangesIt() {
        let songs = (0..<60).map { _ in song(plays: 3, last: 40) }
        let a = MixBuilder.make(.daily, from: songs, now: now, seed: 5, size: 20)
        let b = MixBuilder.make(.daily, from: songs, now: now, seed: 5, size: 20)
        let c = MixBuilder.make(.daily, from: songs, now: now, seed: 6, size: 20)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.count, 20)
        XCTAssertEqual(Set(a).count, 20, "no duplicates")
    }

    func testSmallLibraryReturnsEverythingOnce() {
        let songs = (0..<4).map { _ in song() }
        let mix = MixBuilder.make(.daily, from: songs, now: now, seed: 1, size: 25)
        XCTAssertEqual(Set(mix), Set(songs.map(\.id)))
        XCTAssertTrue(MixBuilder.make(.daily, from: [], now: now).isEmpty)
    }

    func testDeepCutsOnlyRarelyPlayedOlderSongs() {
        let rare = song(plays: 1, added: 60), loved = song(plays: 30, added: 60), brandNew = song(plays: 0, added: 2)
        let mix = MixBuilder.make(.deepCuts, from: [rare, loved, brandNew], now: now, seed: 1)
        XCTAssertEqual(mix, [rare.id])
    }

    func testFreshOnlyRecentImports() {
        let recent = song(added: 5), old = song(added: 90)
        XCTAssertEqual(MixBuilder.make(.fresh, from: [recent, old], now: now, seed: 1), [recent.id])
    }

    func testFavoritesAreDrawnMoreOftenThanRecentlyPlayed() {
        // Over many seeds a favorite shows up in a short mix more often than a song played yesterday.
        let fav = song(plays: 5, last: 40, fav: true)
        let stale = song(plays: 5, last: 0.5)
        let filler = (0..<8).map { _ in song(plays: 5, last: 10) }
        var favHits = 0, staleHits = 0
        for seed in 0..<200 {
            let mix = MixBuilder.make(.daily, from: [fav, stale] + filler, now: now, seed: UInt64(seed), size: 3)
            if mix.contains(fav.id) { favHits += 1 }
            if mix.contains(stale.id) { staleHits += 1 }
        }
        XCTAssertGreaterThan(favHits, staleHits * 2)
    }

    func testArtistsAreSpreadWhenPossible() {
        let songs = [song("X"), song("X"), song("X"), song("Y"), song("Z")]
        let spread = MixBuilder.spreadArtists(songs)
        for pair in zip(spread, spread.dropFirst()) { XCTAssertNotEqual(pair.0.artist, pair.1.artist) }
        XCTAssertEqual(Set(spread.map(\.id)), Set(songs.map(\.id)))
    }

    func testSpreadKeepsOrderWhenImpossible() {
        let songs = [song("X"), song("X"), song("X")]
        XCTAssertEqual(MixBuilder.spreadArtists(songs).map(\.id), songs.map(\.id))
    }

    func testDaySeedChangesPerDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d1 = MixBuilder.daySeed(for: now, calendar: cal)
        let d2 = MixBuilder.daySeed(for: now.addingTimeInterval(day), calendar: cal)
        XCTAssertNotEqual(d1, d2)
        XCTAssertEqual(d1, MixBuilder.daySeed(for: now.addingTimeInterval(60), calendar: cal))
    }
}

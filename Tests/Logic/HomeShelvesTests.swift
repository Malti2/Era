import XCTest
@testable import Era

final class HomeShelvesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    func testNeverPlayedSkipsFreshImportsAndPlayedSongsOldestFirst() {
        let old = ShelfSong(dateAdded: days(90))
        let older = ShelfSong(dateAdded: days(200))
        let fresh = ShelfSong(dateAdded: days(1))
        let played = ShelfSong(playCount: 2, lastPlayedAt: days(5), dateAdded: days(100))
        let result = HomeShelves.neverPlayed([old, fresh, played, older], now: now)
        XCTAssertEqual(result, [older.id, old.id])
    }

    func testNeverPlayedHonorsLimit() {
        let songs = (0..<5).map { ShelfSong(dateAdded: days(10 + Double($0))) }
        XCTAssertEqual(HomeShelves.neverPlayed(songs, now: now, limit: 2).count, 2)
    }

    func testRediscoverNeedsOldPlayAndRanksFavoritesThenPlayCount() {
        let recent = ShelfSong(playCount: 50, lastPlayedAt: days(2))
        let fav = ShelfSong(playCount: 1, lastPlayedAt: days(40), isFavorite: true)
        let often = ShelfSong(playCount: 9, lastPlayedAt: days(60))
        let rare = ShelfSong(playCount: 2, lastPlayedAt: days(90))
        let never = ShelfSong()
        let result = HomeShelves.rediscover([recent, rare, never, often, fav], now: now)
        XCTAssertEqual(result, [fav.id, often.id, rare.id])
    }
}

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

    func testThrowbackFindsSongsAddedAroundThisTimeInEarlierYears() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        func added(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        let lastYearNear = ShelfSong(id: UUID(), dateAdded: added(2025, 11, 4))
        let lastYearFar = ShelfSong(id: UUID(), dateAdded: added(2025, 11, 12))
        let tooFar = ShelfSong(id: UUID(), dateAdded: added(2025, 9, 1))
        let twoYears = ShelfSong(id: UUID(), dateAdded: added(2024, 11, 5))

        let result = HomeShelves.throwback([tooFar, lastYearFar, twoYears, lastYearNear], now: now, calendar: calendar)
        XCTAssertEqual(result, HomeShelves.Throwback(yearsAgo: 1, ids: [lastYearNear.id, lastYearFar.id]))
        XCTAssertEqual(HomeShelves.throwback([twoYears, tooFar], now: now, calendar: calendar)?.yearsAgo, 2)
        XCTAssertNil(HomeShelves.throwback([tooFar], now: now, calendar: calendar))
        XCTAssertNil(HomeShelves.throwback([], now: now, calendar: calendar))
    }
}

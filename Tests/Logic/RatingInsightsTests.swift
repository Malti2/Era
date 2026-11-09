import XCTest
@testable import Era

final class RatingInsightsTests: XCTestCase {
    func testStatsCountDistributionAverageAndClamping() {
        let stats = RatingStats.make(from: [0, 0, 5, 4, 4, 9, -2])
        XCTAssertEqual(stats.total, 7)
        XCTAssertEqual(stats.unrated, 3)           // 0, 0 and the clamped -2
        XCTAssertEqual(stats.rated, 4)
        XCTAssertEqual(stats.count(for: 5), 2)     // 5 and the clamped 9
        XCTAssertEqual(stats.count(for: 4), 2)
        XCTAssertEqual(stats.topRated, 4)
        XCTAssertEqual(stats.average, 4.5, accuracy: 0.0001)
        XCTAssertEqual(stats.share(of: 4), 0.5, accuracy: 0.0001)
    }

    func testEmptyAndUnratedLibrariesHaveZeroAverage() {
        XCTAssertEqual(RatingStats.make(from: []).average, 0)
        let unrated = RatingStats.make(from: [0, 0])
        XCTAssertEqual(unrated.average, 0)
        XCTAssertEqual(unrated.share(of: 3), 0)
    }

    private func candidate(_ n: UInt8, rating: Int = 0, plays: Int = 0, fav: Bool = false,
                           last: Double? = nil, added: Double = 0) -> RatingCandidate {
        RatingCandidate(id: UUID(uuid: (n, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), rating: rating, playCount: plays,
                        isFavorite: fav, lastPlayedAt: last.map { Date(timeIntervalSince1970: $0) },
                        dateAdded: Date(timeIntervalSince1970: added))
    }

    func testQueueSkipsRatedAndRanksByPlaysThenFavorite() {
        let rated = candidate(1, rating: 3, plays: 99)
        let often = candidate(2, plays: 5)
        let fav = candidate(3, plays: 1, fav: true)    // 2 + 3 = 5
        let once = candidate(4, plays: 1)
        let queue = RatingReview.queue(from: [rated, once, fav, often])
        XCTAssertFalse(queue.contains(rated.id))
        XCTAssertEqual(queue.first, often.id)          // 10 beats 5
        XCTAssertEqual(queue.last, once.id)
        XCTAssertEqual(queue.count, 3)
    }

    func testQueueTieBreaksOnRecentPlayThenNewestThenId() {
        let a = candidate(1, plays: 2, last: 100)
        let b = candidate(2, plays: 2, last: 200)
        let never = candidate(3, plays: 2)
        let newer = candidate(4, added: 50)
        let older = candidate(5, added: 10)
        XCTAssertEqual(RatingReview.queue(from: [never, a, b]), [b.id, a.id, never.id])
        XCTAssertEqual(RatingReview.queue(from: [older, newer]), [newer.id, older.id])
        let twin1 = candidate(7), twin2 = candidate(6)
        XCTAssertEqual(RatingReview.queue(from: [twin1, twin2]), [twin2.id, twin1.id])
    }

    func testQueueHonorsLimit() {
        let all = (1...10).map { candidate(UInt8($0), plays: $0) }
        XCTAssertEqual(RatingReview.queue(from: all, limit: 3).count, 3)
        XCTAssertTrue(RatingReview.queue(from: all, limit: 0).isEmpty)
    }

    func testPlaylistSortByRatingKeepsUnratedLastAndStable() {
        let a = PlaylistRow(title: "A", rating: 0), b = PlaylistRow(title: "B", rating: 5)
        let c = PlaylistRow(title: "C", rating: 3), d = PlaylistRow(title: "D", rating: 3)
        let ids = PlaylistSortOrder.rating.ordered([a, c, b, d, ])
        XCTAssertEqual(ids, [b.id, c.id, d.id, a.id])
    }
}

final class RatingPromptTests: XCTestCase {
    private func song(plays: Int, rating: Int = 0) -> RatingCandidate {
        RatingCandidate(id: UUID(), rating: rating, playCount: plays, isFavorite: false, lastPlayedAt: nil, dateAdded: Date(timeIntervalSince1970: 0))
    }

    func testPromptCountsOnlyPlayedUnratedSongs() {
        let list = [song(plays: 5), song(plays: 2), song(plays: 1), song(plays: 9, rating: 3), song(plays: 0)]
        XCTAssertEqual(RatingReview.promptCount(from: list), 2)
    }

    func testPromptNeedsEnoughSongsAndRespectsSnooze() {
        let now = Date()
        let few = (0..<4).map { _ in song(plays: 3) }
        let enough = (0..<5).map { _ in song(plays: 3) }
        XCTAssertFalse(RatingReview.isPromptDue(candidates: few, snoozedUntil: nil, now: now))
        XCTAssertTrue(RatingReview.isPromptDue(candidates: enough, snoozedUntil: nil, now: now))
        XCTAssertFalse(RatingReview.isPromptDue(candidates: enough, snoozedUntil: now.addingTimeInterval(60), now: now))
        XCTAssertTrue(RatingReview.isPromptDue(candidates: enough, snoozedUntil: now.addingTimeInterval(-60), now: now))
        XCTAssertGreaterThan(RatingReview.snoozeDate(from: now), now.addingTimeInterval(20 * 86_400))
    }
}

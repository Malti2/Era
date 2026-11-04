import XCTest
@testable import Era

final class PlayHistoryTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func entry(_ title: String, _ when: Date, artist: String = "", seconds: Double = 100, song: UUID? = nil) -> HistoryEntry {
        HistoryEntry(date: when, seconds: seconds, title: title, artist: artist, songID: song)
    }

    func testDaysAreGroupedNewestFirst() {
        let entries = [entry("a", date(3, 1, 9)), entry("b", date(3, 2, 8)), entry("c", date(3, 1, 20)), entry("d", date(3, 2, 22))]
        let days = PlayHistory.days(entries, calendar: calendar)
        XCTAssertEqual(days.map(\.plays), [2, 2])
        XCTAssertEqual(days[0].day, calendar.startOfDay(for: date(3, 2)))
        XCTAssertEqual(days[0].entries.map(\.title), ["d", "b"])
        XCTAssertEqual(days[1].entries.map(\.title), ["c", "a"])
    }

    func testEmptyHistoryHasNoDays() {
        XCTAssertTrue(PlayHistory.days([], calendar: calendar).isEmpty)
    }

    func testDayTotalsAndUniqueSongs() {
        let id = UUID()
        let entries = [entry("a", date(3, 1, 9), seconds: 60, song: id), entry("a", date(3, 1, 10), seconds: 90, song: id),
                       entry("b", date(3, 1, 11), seconds: 30)]
        let day = PlayHistory.days(entries, calendar: calendar)[0]
        XCTAssertEqual(day.plays, 3)
        XCTAssertEqual(day.seconds, 180)
        XCTAssertEqual(day.uniqueSongs, 2)
    }

    func testEntriesWithoutSongIDAreMergedByTitleAndArtist() {
        let entries = [entry("Same", date(3, 1, 9), artist: "Ä"), entry("same", date(3, 1, 10), artist: "a"), entry("Same", date(3, 1, 11), artist: "B")]
        XCTAssertEqual(PlayHistory.days(entries, calendar: calendar)[0].uniqueSongs, 2)
    }

    func testDayLabels() {
        let now = date(3, 10, 15)
        XCTAssertEqual(PlayHistory.label(for: calendar.startOfDay(for: date(3, 10, 1)), now: now, calendar: calendar), .today)
        XCTAssertEqual(PlayHistory.label(for: calendar.startOfDay(for: date(3, 9, 23)), now: now, calendar: calendar), .yesterday)
        let older = calendar.startOfDay(for: date(3, 8))
        XCTAssertEqual(PlayHistory.label(for: older, now: now, calendar: calendar), .date(older))
    }

    func testYesterdayAcrossMonthBoundary() {
        let now = date(4, 1, 8)
        XCTAssertEqual(PlayHistory.label(for: calendar.startOfDay(for: date(3, 31)), now: now, calendar: calendar), .yesterday)
    }

    func testFilterRequiresAllTermsAndIgnoresAccents() {
        let entries = [entry("Café Nights", date(3, 1), artist: "Mira"), entry("Night Drive", date(3, 1), artist: "Cafe Club"), entry("Other", date(3, 1))]
        XCTAssertEqual(PlayHistory.filter(entries, query: "cafe night").map(\.title), ["Café Nights"])
        XCTAssertEqual(PlayHistory.filter(entries, query: "CAFE").count, 2)
        XCTAssertEqual(PlayHistory.filter(entries, query: "   ").count, 3, "blank query keeps everything")
        XCTAssertTrue(PlayHistory.filter(entries, query: "zzz").isEmpty)
    }

    func testRankSharesPlacesOnTies() {
        XCTAssertEqual(SongRank.make(playCount: 5, higher: 0, total: 40), SongRank(position: 1, total: 40))
        XCTAssertEqual(SongRank.make(playCount: 5, higher: 7, total: 40), SongRank(position: 8, total: 40))
    }

    func testUnplayedSongsHaveNoRank() {
        XCTAssertNil(SongRank.make(playCount: 0, higher: 0, total: 40))
        XCTAssertNil(SongRank.make(playCount: 3, higher: 0, total: 0))
        XCTAssertNil(SongRank.make(playCount: 3, higher: -1, total: 10))
    }

    func testRankPositionIsClampedToTotal() {
        XCTAssertEqual(SongRank.make(playCount: 1, higher: 99, total: 10)?.position, 10)
    }

    func testTopPercentOnlyForTopTenPercentOfBigLibraries() {
        XCTAssertEqual(SongRank(position: 1, total: 200).topPercent, 1)
        XCTAssertEqual(SongRank(position: 20, total: 200).topPercent, 10)
        XCTAssertNil(SongRank(position: 21, total: 200).topPercent)
        XCTAssertNil(SongRank(position: 1, total: 5).topPercent, "tiny libraries do not get a badge")
    }
}

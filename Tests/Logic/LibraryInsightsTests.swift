import XCTest
@testable import Era

final class LibraryInsightsTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() { calendar.timeZone = TimeZone(secondsFromGMT: 0)! }

    private func song(_ statuses: [String] = [], era: String = "", year: Int = 2025, versions: Int = 1, duration: Double = 100,
                      plays: Int = 0, favorite: Bool = false, notes: Bool = false, markers: Int = 0) -> InsightSong {
        InsightSong(statuses: statuses, era: era, dateAdded: calendar.date(from: DateComponents(year: year, month: 6, day: 1))!,
                    versionCount: versions, duration: duration, playCount: plays, isFavorite: favorite, hasNotes: notes, markerCount: markers)
    }

    func testEmptyLibrary() {
        let insights = LibraryInsights.make(from: [], calendar: calendar)
        XCTAssertTrue(insights.isEmpty)
        XCTAssertEqual(insights.averageVersions, 0)
        XCTAssertTrue(insights.addedPerYear.isEmpty)
    }

    func testTotals() {
        let insights = LibraryInsights.make(from: [
            song(versions: 3, duration: 200, plays: 2, favorite: true, notes: true, markers: 4),
            song(versions: 1, duration: 100),
            song(versions: 2, duration: 50, plays: 1, markers: 1)
        ], calendar: calendar)
        XCTAssertEqual(insights.songs, 3)
        XCTAssertEqual(insights.versions, 6)
        XCTAssertEqual(insights.totalSeconds, 350)
        XCTAssertEqual(insights.favorites, 1)
        XCTAssertEqual(insights.neverPlayed, 1)
        XCTAssertEqual(insights.withNotes, 1)
        XCTAssertEqual(insights.markers, 5)
        XCTAssertEqual(insights.multiVersion, 2)
        XCTAssertEqual(insights.averageVersions, 2)
    }

    func testStatusesAreCountedPerSongAndSortedByCount() {
        let insights = LibraryInsights.make(from: [
            song(["Demo"]), song(["Demo", "Leak"]), song(["Released"]), song(), song(["Demo", "Demo"])
        ], unknownName: "Unknown", calendar: calendar)
        XCTAssertEqual(insights.statuses.map(\.name), ["Demo", "Leak", "Released", "Unknown"])
        XCTAssertEqual(insights.statuses.first, .init(name: "Demo", count: 3), "a repeated status counts once per song")
    }

    func testErasIgnoreBlanksAndAreLimited() {
        let list = (1...7).flatMap { index in (0..<index).map { _ in song(era: "Era \(index)") } } + [song(era: "  "), song()]
        let insights = LibraryInsights.make(from: list, eraLimit: 3, calendar: calendar)
        XCTAssertEqual(insights.eras.map(\.name), ["Era 7", "Era 6", "Era 5"])
    }

    func testAddedPerYearFillsGaps() {
        let insights = LibraryInsights.make(from: [song(year: 2022), song(year: 2022), song(year: 2025)], calendar: calendar)
        XCTAssertEqual(insights.addedPerYear.map(\.year), [2022, 2023, 2024, 2025])
        XCTAssertEqual(insights.addedPerYear.map(\.count), [2, 0, 0, 1])
    }
}

import XCTest
@testable import Era

final class LibraryLogicTests: XCTestCase {
    // MARK: Duplicates

    private func item(_ title: String, _ artist: String) -> DuplicateFinder.Item {
        DuplicateFinder.Item(id: UUID(), title: title, artist: artist)
    }

    func testDuplicatesIgnoreCaseAccentsAndQualifiers() {
        let a = item("Café Song", "The Band"), b = item("cafe song (Remastered 2011)", "Band"), c = item("Cafe Song - Live", "BAND")
        let other = item("Different", "Band")
        let groups = DuplicateFinder.groups([a, b, c, other])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0]), Set([a.id, b.id, c.id]))
    }

    func testDifferentArtistsAreNotDuplicates() {
        XCTAssertTrue(DuplicateFinder.groups([item("Intro", "A"), item("Intro", "B")]).isEmpty)
    }

    func testEmptyTitlesAreIgnored() {
        XCTAssertTrue(DuplicateFinder.groups([item("", "A"), item("()", "A")]).isEmpty)
    }

    // MARK: Search

    private func doc(_ title: String, artist: String = "", album: String = "", tags: [String] = [], versions: [String] = []) -> LibrarySearch.Document {
        LibrarySearch.Document(id: UUID(), title: title, artist: artist, album: album, era: "", tags: tags, versions: versions)
    }

    func testSearchRequiresAllWordsInAnyField() {
        let match = doc("Night Drive", artist: "Neon", tags: ["synth"])
        let miss = doc("Night Walk", artist: "Neon")
        XCTAssertEqual(LibrarySearch.search([miss, match], query: "night synth"), [match.id])
    }

    func testSearchIgnoresAccentsAndCase() {
        let d = doc("Über Alles")
        XCTAssertEqual(LibrarySearch.search([d], query: "UBER"), [d.id])
    }

    func testTitleMatchesRankBeforeOtherFields() {
        let byArtist = doc("Something", artist: "Rain")
        let byTitle = doc("Rain Dance")
        XCTAssertEqual(LibrarySearch.search([byArtist, byTitle], query: "rain"), [byTitle.id, byArtist.id])
    }

    func testBlankQueryFindsNothing() {
        XCTAssertTrue(LibrarySearch.search([doc("A")], query: "   ").isEmpty)
    }

    // MARK: Rediscover

    func testRediscoverPicksStaleSongsFavoritesFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func days(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }
        let fresh = HomeShelves.Candidate(id: UUID(), playCount: 3, lastPlayedAt: days(2), dateAdded: days(90), isFavorite: true)
        let staleFav = HomeShelves.Candidate(id: UUID(), playCount: 3, lastPlayedAt: days(40), dateAdded: days(90), isFavorite: true)
        let staleOld = HomeShelves.Candidate(id: UUID(), playCount: 1, lastPlayedAt: days(100), dateAdded: days(120), isFavorite: false)
        let neverNew = HomeShelves.Candidate(id: UUID(), playCount: 0, lastPlayedAt: nil, dateAdded: days(3), isFavorite: false)
        let neverOld = HomeShelves.Candidate(id: UUID(), playCount: 0, lastPlayedAt: nil, dateAdded: days(20), isFavorite: false)
        let ids = HomeShelves.rediscover([fresh, staleFav, staleOld, neverNew, neverOld], now: now)
        XCTAssertEqual(ids, [staleFav.id, staleOld.id, neverOld.id])
    }
}

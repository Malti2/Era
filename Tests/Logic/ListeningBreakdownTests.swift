import XCTest
@testable import Era

final class ListeningBreakdownTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()
    private lazy var songs: [UUID: ListeningSong] = [
        a: ListeningSong(album: "Sketches", era: "Synth", tags: ["night", "slow"], statuses: ["Demo"]),
        b: ListeningSong(album: "Sketches", era: "Synth", tags: ["night"], statuses: ["Released"]),
        c: ListeningSong(album: "", era: "", tags: [], statuses: []),
    ]

    private func rec(_ id: UUID?, _ seconds: Double) -> PlayRecord {
        PlayRecord(date: Date(timeIntervalSince1970: 0), seconds: seconds, title: "t", artist: "a", songID: id)
    }

    func testStatusSharesAreSortedBySecondsAndRelativeToTotal() {
        let records = [rec(a, 100), rec(a, 100), rec(b, 100), rec(c, 100)]
        let result = ListeningBreakdown.make(.status, records: records, songs: songs, unknownName: "None")
        XCTAssertEqual(result.map(\.name), ["Demo", "None", "Released"], "ties on seconds are ordered by name")
        XCTAssertEqual(result[0].plays, 2)
        XCTAssertEqual(result[0].share, 0.5, accuracy: 0.0001)
    }

    func testMultiTagSongCountsForEveryTag() {
        let result = ListeningBreakdown.make(.tag, records: [rec(a, 60), rec(b, 60)], songs: songs)
        let byName = Dictionary(uniqueKeysWithValues: result.map { ($0.name, $0) })
        XCTAssertEqual(byName["night"]?.plays, 2)
        XCTAssertEqual(byName["slow"]?.plays, 1)
        XCTAssertEqual(byName["night"]?.share ?? 0, 1, accuracy: 0.0001)
    }

    func testUnknownSongsAndMissingIDsAreIgnored() {
        let result = ListeningBreakdown.make(.album, records: [rec(nil, 500), rec(UUID(), 500), rec(a, 30)], songs: songs)
        XCTAssertEqual(result.map(\.name), ["Sketches"])
        XCTAssertEqual(result[0].share, 1, accuracy: 0.0001)
    }

    func testZeroSecondsFallBackToPlayShares() {
        let result = ListeningBreakdown.make(.era, records: [rec(a, 0), rec(c, 0)], songs: songs, unknownName: "No Era")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.share ?? 0, 0.5, accuracy: 0.0001)
    }

    func testLimitAndCaseInsensitiveGrouping() {
        var many = songs
        let d = UUID(), e = UUID()
        many[d] = ListeningSong(tags: ["Chill"])
        many[e] = ListeningSong(tags: ["chill"])
        let merged = ListeningBreakdown.make(.tag, records: [rec(d, 10), rec(e, 10)], songs: many)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].plays, 2)
        let limited = ListeningBreakdown.make(.tag, records: [rec(a, 10), rec(b, 5)], songs: songs, limit: 1)
        XCTAssertEqual(limited.count, 1)
    }

    func testAvailableDimensionsSkipEmptyOnes() {
        let plain = [ListeningSong(statuses: ["Demo"]), ListeningSong(statuses: ["Leak"])]
        XCTAssertEqual(ListeningBreakdown.availableDimensions(songs: plain), [.status])
        XCTAssertEqual(ListeningBreakdown.availableDimensions(songs: Array(songs.values)), [.status, .era, .tag, .album])
        XCTAssertTrue(ListeningBreakdown.availableDimensions(songs: []).isEmpty)
    }
}

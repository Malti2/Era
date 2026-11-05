import XCTest
import SwiftData
@testable import Era

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var store: EraStore!
    private var context: ModelContext!

    override func setUp() async throws {
        context = ModelContext(Persistence.makeContainer(inMemory: true))
        store = EraStore(context: context)
    }

    private func addEvent(_ song: UUID?, title: String = "T") -> PlayEvent {
        let event = PlayEvent(date: Date(), seconds: 60, songID: song, title: title, artist: "A")
        context.insert(event)
        try? context.save()
        return event
    }

    private func eventCount() -> Int { (try? context.fetchCount(FetchDescriptor<PlayEvent>())) ?? -1 }

    func testDeleteSelectedEventsOnly() {
        let a = addEvent(UUID()), b = addEvent(UUID()), c = addEvent(nil)
        XCTAssertEqual(store.deletePlayEvents(ids: [a.id, c.id, UUID()]), 2)
        XCTAssertEqual(eventCount(), 1)
        XCTAssertEqual(store.deletePlayEvents(ids: []), 0)
        _ = b
    }

    func testClearHistoryOfOneSongKeepsTheRest() {
        let song = UUID()
        _ = addEvent(song); _ = addEvent(song); _ = addEvent(UUID())
        XCTAssertEqual(store.clearPlayHistory(songID: song), 2)
        XCTAssertEqual(eventCount(), 1)
    }

    func testClearWholeHistory() {
        _ = addEvent(UUID()); _ = addEvent(nil)
        XCTAssertEqual(store.clearPlayHistory(), 2)
        XCTAssertEqual(eventCount(), 0)
        XCTAssertEqual(store.clearPlayHistory(), 0)
    }

    func testSongsPlayedMoreAndCount() {
        for (index, plays) in [5, 3, 3, 0].enumerated() {
            let song = Song(title: "S\(index)")
            song.playCount = plays
            store.insertSong(song)
        }
        XCTAssertEqual(store.songCount(), 4)
        XCTAssertEqual(store.songsPlayedMore(than: 3), 1)
        XCTAssertEqual(store.songsPlayedMore(than: 5), 0)
        XCTAssertEqual(store.songsPlayedMore(than: 0), 3)
    }

    func testDeletingEventsLowersThePlayCountButNotBelowZero() {
        let song = Song(title: "Counted")
        song.playCount = 3
        context.insert(song)
        let events = [addEvent(song.id), addEvent(song.id)]
        XCTAssertEqual(store.deletePlayEvents(ids: [events[0].id]), 1)
        XCTAssertEqual(song.playCount, 2)
        XCTAssertEqual(store.clearPlayHistory(songID: song.id), 1)
        XCTAssertEqual(song.playCount, 1)
        song.playCount = 0
        _ = addEvent(song.id)
        XCTAssertEqual(store.clearPlayHistory(), 1)
        XCTAssertEqual(song.playCount, 0)
    }
}

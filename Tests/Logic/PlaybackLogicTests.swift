import XCTest
@testable import Era

final class SleepTimerStateTests: XCTestCase {
    func testCountdownFadesInLastSecondsAndExpires() {
        var timer = SleepTimerState()
        timer.start(minutes: 1)
        XCTAssertEqual(timer.remaining, 60)
        var events: [SleepTimerState.Event] = []
        for _ in 0..<60 { events.append(timer.tick()) }
        XCTAssertTrue(events.prefix(54).allSatisfy { $0 == .none })
        XCTAssertEqual(events[54], .fade(1.0))
        XCTAssertEqual(events[58], .fade(0.2))
        XCTAssertEqual(events[59], .expired)
        XCTAssertFalse(timer.isActive)
        XCTAssertEqual(timer.tick(), .none, "an idle timer stays quiet")
    }

    func testEndOfTrackStopsOnceAndOnlyWhenArmed() {
        var timer = SleepTimerState()
        XCTAssertFalse(timer.trackFinished())
        timer.startEndOfTrack()
        XCTAssertTrue(timer.stopsAtTrackEnd)
        XCTAssertEqual(timer.tick(), .none)
        XCTAssertTrue(timer.trackFinished())
        XCTAssertFalse(timer.isActive)
        XCTAssertFalse(timer.trackFinished())
    }

    func testEndOfTrackFadesInLastSeconds() {
        var timer = SleepTimerState()
        timer.startEndOfTrack()
        XCTAssertEqual(timer.tick(remainingSeconds: 120), .none)
        XCTAssertEqual(timer.tick(remainingSeconds: 6), .none)
        XCTAssertEqual(timer.tick(remainingSeconds: 5), .fade(1.0))
        XCTAssertEqual(timer.tick(remainingSeconds: 2.5), .fade(0.5))
        XCTAssertEqual(timer.tick(remainingSeconds: 0.5), .fade(0.1))
        XCTAssertEqual(timer.tick(remainingSeconds: nil), .none)
        XCTAssertEqual(timer.tick(remainingSeconds: 0), .none)
        XCTAssertTrue(timer.isActive, "fade ticks must not disarm the timer")
    }

    func testCountdownIgnoresRemainingSeconds() {
        var timer = SleepTimerState()
        timer.start(minutes: 1)
        XCTAssertEqual(timer.tick(remainingSeconds: 1), .none, "one second left in countdown, no fade yet")
        XCTAssertEqual(timer.remaining, 59)
    }

    func testCancelAndRestartReplaceMode() {
        var timer = SleepTimerState()
        timer.start(minutes: 5)
        timer.startEndOfTrack()
        XCTAssertNil(timer.remaining)
        timer.start(minutes: 0)
        XCTAssertFalse(timer.isActive)
        timer.start(minutes: 2)
        timer.cancel()
        XCTAssertFalse(timer.isActive)
    }

    func testExtendAddsMinutesToCountdown() {
        var timer = SleepTimerState()
        timer.start(minutes: 5)
        _ = timer.tick()
        timer.extend(minutes: 15)
        XCTAssertEqual(timer.remaining, 299 + 900)
        timer.extend(minutes: 0)
        XCTAssertEqual(timer.remaining, 299 + 900, "zero minutes change nothing")
        timer.extend(minutes: -5)
        XCTAssertEqual(timer.remaining, 299 + 900, "negative minutes change nothing")
    }

    func testExtendDoesNothingWithoutCountdown() {
        var timer = SleepTimerState()
        timer.extend(minutes: 15)
        XCTAssertFalse(timer.isActive)
        timer.startEndOfTrack()
        timer.extend(minutes: 15)
        XCTAssertTrue(timer.stopsAtTrackEnd)
        XCTAssertNil(timer.remaining)
    }

    func testAfterSongsCountsDownToStop() {
        var timer = SleepTimerState()
        timer.startAfterSongs(3)
        XCTAssertEqual(timer.remainingSongs, 3)
        XCTAssertTrue(timer.isActive)
        XCTAssertFalse(timer.isLastSong)
        XCTAssertFalse(timer.trackFinished())
        XCTAssertEqual(timer.remainingSongs, 2)
        XCTAssertFalse(timer.trackFinished())
        XCTAssertEqual(timer.remainingSongs, 1)
        XCTAssertTrue(timer.isLastSong)
        XCTAssertTrue(timer.trackFinished())
        XCTAssertFalse(timer.isActive)
        XCTAssertNil(timer.remainingSongs)
        XCTAssertFalse(timer.trackFinished())
    }

    func testAfterSongsWithOneStopsLikeEndOfTrack() {
        var timer = SleepTimerState()
        timer.startAfterSongs(1)
        XCTAssertTrue(timer.isLastSong)
        XCTAssertTrue(timer.fadesAtTrackEnd)
        XCTAssertTrue(timer.trackFinished())
        XCTAssertFalse(timer.isActive)
    }

    func testAfterSongsIgnoresZeroAndNegative() {
        var timer = SleepTimerState()
        timer.startAfterSongs(0)
        XCTAssertFalse(timer.isActive)
        timer.startAfterSongs(-3)
        XCTAssertFalse(timer.isActive)
    }

    func testAfterSongsFadesOnlyOnLastSong() {
        var timer = SleepTimerState()
        timer.startAfterSongs(2)
        XCTAssertFalse(timer.fadesAtTrackEnd)
        XCTAssertEqual(timer.tick(remainingSeconds: 2), .none, "not the last song yet, no fade")
        XCTAssertFalse(timer.trackFinished())
        XCTAssertTrue(timer.fadesAtTrackEnd)
        XCTAssertEqual(timer.tick(remainingSeconds: 120), .none)
        XCTAssertEqual(timer.tick(remainingSeconds: 2.5), .fade(0.5))
        XCTAssertEqual(timer.tick(remainingSeconds: nil), .none)
        XCTAssertTrue(timer.isActive, "fade ticks must not disarm the timer")
    }

    func testSkipCountsTowardSongsButNotOtherModes() {
        var timer = SleepTimerState()
        XCTAssertFalse(timer.songSkipped(), "idle timer: skip changes nothing")
        timer.start(minutes: 5)
        XCTAssertFalse(timer.songSkipped())
        XCTAssertEqual(timer.remaining, 300)
        timer.startEndOfTrack()
        XCTAssertFalse(timer.songSkipped(), "end-of-track: skip must not stop playback")
        XCTAssertTrue(timer.stopsAtTrackEnd)
        timer.startAfterSongs(2)
        XCTAssertFalse(timer.songSkipped())
        XCTAssertEqual(timer.remainingSongs, 1)
        XCTAssertTrue(timer.songSkipped())
        XCTAssertFalse(timer.isActive)
    }

    func testExtendDoesNothingInAfterSongs() {
        var timer = SleepTimerState()
        timer.startAfterSongs(3)
        timer.extend(minutes: 15)
        XCTAssertEqual(timer.remainingSongs, 3)
    }

    func testModeSwitchesReplaceEachOther() {
        var timer = SleepTimerState()
        timer.start(minutes: 5)
        timer.startAfterSongs(2)
        XCTAssertNil(timer.remaining)
        XCTAssertEqual(timer.remainingSongs, 2)
        timer.startEndOfTrack()
        XCTAssertNil(timer.remainingSongs)
        XCTAssertTrue(timer.stopsAtTrackEnd)
        timer.startAfterSongs(4)
        XCTAssertFalse(timer.stopsAtTrackEnd)
        XCTAssertEqual(timer.remainingSongs, 4)
    }
}

final class PlaybackSnapshotTests: XCTestCase {
    private let ids = (0..<4).map { _ in UUID() }

    private func snapshot(current: Int, position: Double = 90) -> PlaybackSnapshot {
        PlaybackSnapshot(queue: ids, current: ids[current], position: position, shuffle: false, repeatMode: 0)
    }

    func testRestoresEverythingWhenAllVersionsExist() {
        let restored = snapshot(current: 2).restored(available: Set(ids), durations: [ids[2]: 200])
        XCTAssertEqual(restored, .init(queue: ids, current: ids[2], position: 90))
    }

    func testDropsMissingVersionsAndAdvancesWhenCurrentIsGone() {
        let available = Set([ids[0], ids[3]])
        let restored = snapshot(current: 1).restored(available: available)
        XCTAssertEqual(restored?.queue, [ids[0], ids[3]])
        XCTAssertEqual(restored?.current, ids[3])
        XCTAssertEqual(restored?.position, 0)
    }

    func testFallsBackToFirstWhenNothingFollowsTheMissingCurrent() {
        let restored = snapshot(current: 3).restored(available: Set([ids[0]]))
        XCTAssertEqual(restored?.current, ids[0])
    }

    func testNothingLeftMeansNoRestore() {
        XCTAssertNil(snapshot(current: 0).restored(available: []))
    }

    func testPositionNearStartOrEndResets() {
        XCTAssertEqual(PlaybackSnapshot.clamp(2, duration: 200), 0)
        XCTAssertEqual(PlaybackSnapshot.clamp(198, duration: 200), 0)
        XCTAssertEqual(PlaybackSnapshot.clamp(100, duration: 200), 100)
        XCTAssertEqual(PlaybackSnapshot.clamp(100, duration: nil), 100)
        XCTAssertEqual(PlaybackSnapshot.clamp(.nan, duration: 200), 0)
    }

    func testClampBoundaryValues() {
        XCTAssertEqual(PlaybackSnapshot.clamp(3, duration: 200), 0, "exactly 3 seconds in is still the start")
        XCTAssertEqual(PlaybackSnapshot.clamp(3.5, duration: 200), 3.5)
        XCTAssertEqual(PlaybackSnapshot.clamp(197, duration: 200), 197, "exactly duration-3 is kept")
        XCTAssertEqual(PlaybackSnapshot.clamp(-5, duration: 200), 0)
        XCTAssertEqual(PlaybackSnapshot.clamp(.infinity, duration: 200), 0)
        XCTAssertEqual(PlaybackSnapshot.clamp(100, duration: 0), 100, "no duration means no end cap")
        XCTAssertEqual(PlaybackSnapshot.clamp(100, duration: -10), 100)
    }

    func testRestoreWhenCurrentIsNotInQueue() {
        // current fehlt in der Queue (altes Snapshot): ab Index 0 weitersuchen.
        let snapshot = PlaybackSnapshot(queue: [ids[0], ids[1]], current: UUID(), position: 90, shuffle: false, repeatMode: 0)
        let restored = snapshot.restored(available: Set(ids))
        XCTAssertEqual(restored?.current, ids[0])
        XCTAssertEqual(restored?.position, 0)
    }

    func testLoadReturnsNilForCorruptData() {
        let suite = UserDefaults(suiteName: "era.tests.\(UUID().uuidString)")!
        suite.set(Data("kein json".utf8), forKey: PlaybackSnapshot.storageKey)
        XCTAssertNil(PlaybackSnapshot.load(from: suite))
        suite.removeObject(forKey: PlaybackSnapshot.storageKey)
        XCTAssertNil(PlaybackSnapshot.load(from: suite))
    }

    func testLoadToleratesOldSnapshotsWithoutNewFields() throws {
        // Altes JSON ohne shuffle/repeatMode/position: Queue und Titel muessen
        // trotzdem wiederherstellbar sein, statt die Session zu verlieren.
        let legacy = """
        {"queue": ["\(ids[0])", "\(ids[1])"], "current": "\(ids[1])"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PlaybackSnapshot.self, from: legacy)
        XCTAssertEqual(decoded.queue, [ids[0], ids[1]])
        XCTAssertEqual(decoded.current, ids[1])
        XCTAssertEqual(decoded.position, 0)
        XCTAssertFalse(decoded.shuffle)
        XCTAssertEqual(decoded.repeatMode, 0)
    }

    func testCodableRoundtripViaDefaults() throws {
        let suite = UserDefaults(suiteName: "era.tests.\(UUID().uuidString)")!
        let original = snapshot(current: 1)
        original.save(to: suite)
        XCTAssertEqual(PlaybackSnapshot.load(from: suite), original)
    }
}

final class ShuffleBagTests: XCTestCase {
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private let queue = (0..<6).map { _ in UUID() }

    func testEveryTrackPlaysOnceBeforeTheBagEnds() {
        var bag = ShuffleBag()
        var generator = Seeded(state: 42)
        var current = queue[0]
        bag.reset(startingWith: current)
        var seen = [current]
        while let next = bag.next(in: queue, current: current, wrap: false, using: &generator) {
            seen.append(next)
            current = next
        }
        XCTAssertEqual(seen.count, queue.count)
        XCTAssertEqual(Set(seen), Set(queue))
    }

    func testWrapStartsNewRoundWithoutImmediateRepeat() {
        var bag = ShuffleBag()
        var generator = Seeded(state: 7)
        var current = queue[0]
        bag.reset(startingWith: current)
        for _ in 0..<(queue.count - 1) { current = bag.next(in: queue, current: current, wrap: true, using: &generator)! }
        let afterWrap = bag.next(in: queue, current: current, wrap: true, using: &generator)
        XCTAssertNotNil(afterWrap)
        XCTAssertNotEqual(afterWrap, current)
    }

    func testPreviousWalksBackThroughHistory() {
        var bag = ShuffleBag()
        var generator = Seeded(state: 1)
        let first = queue[0]
        bag.reset(startingWith: first)
        let second = bag.next(in: queue, current: first, wrap: false, using: &generator)!
        let third = bag.next(in: queue, current: second, wrap: false, using: &generator)!
        XCTAssertEqual(bag.previous(current: third), second)
        XCTAssertEqual(bag.previous(current: second), first)
        XCTAssertNil(bag.previous(current: first))
    }

    func testSingleTrackQueueWithWrapRepeatsItself() {
        var bag = ShuffleBag()
        var generator = Seeded(state: 3)
        let only = queue[0]
        XCTAssertEqual(bag.next(in: [only], current: only, wrap: true, using: &generator), only)
        var fresh = ShuffleBag()
        XCTAssertNil(fresh.next(in: [only], current: only, wrap: false))
    }

    func testEmptyQueueReturnsNil() {
        var bag = ShuffleBag()
        var generator = Seeded(state: 3)
        XCTAssertNil(bag.next(in: [], current: queue[0], wrap: true, using: &generator))
        XCTAssertNil(bag.next(in: [], current: queue[0], wrap: false, using: &generator))
    }

    func testNextAfterExternalJumpContinuesWithoutRepeatingCurrent() {
        var bag = ShuffleBag()
        var generator = Seeded(state: 9)
        bag.reset(startingWith: queue[0])
        // Nutzer springt von aussen auf einen anderen Titel: der Bag merkt es sich
        // als gespielt und liefert danach keinen der beiden mehr.
        let next = bag.next(in: queue, current: queue[3], wrap: false, using: &generator)
        XCTAssertNotNil(next)
        XCTAssertNotEqual(next, queue[0])
        XCTAssertNotEqual(next, queue[3])
    }

    func testResetWithoutStartLeavesHistoryEmpty() {
        var bag = ShuffleBag()
        var generator = Seeded(state: 5)
        bag.reset()
        XCTAssertNil(bag.previous(current: queue[0]))
        XCTAssertNotNil(bag.next(in: queue, current: queue[0], wrap: false, using: &generator))
    }
}

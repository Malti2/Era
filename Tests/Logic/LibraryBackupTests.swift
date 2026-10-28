import XCTest
@testable import Era

final class LibraryBackupTests: XCTestCase {
    private func song(_ title: String, id: UUID = UUID()) -> LibraryBackup.SongEntry {
        LibraryBackup.SongEntry(id: id, title: title, artist: "", album: "", era: "", year: nil, dateAdded: Date(timeIntervalSince1970: 0),
                                playCount: 0, lastPlayedAt: nil, isFavorite: false, resumePosition: 0, primaryVersionID: nil, tagIDs: [])
    }

    private func version(_ songID: UUID, file: String, hash: String = UUID().uuidString, sortIndex: Int = 0, id: UUID = UUID()) -> LibraryBackup.VersionEntry {
        LibraryBackup.VersionEntry(id: id, songID: songID, name: "OG", fileName: file, pcmHash: hash, duration: 100,
                                   dateAdded: Date(timeIntervalSince1970: 0), year: nil, sortIndex: sortIndex)
    }

    private func backup(_ songs: [LibraryBackup.SongEntry], _ versions: [LibraryBackup.VersionEntry],
                        packs: [LibraryBackup.PackEntry] = [], playlists: [LibraryBackup.PlaylistEntry2] = []) -> LibraryBackup {
        LibraryBackup(songs: songs, versions: versions, tags: [], packs: packs, playlists: playlists)
    }

    func testDecodeRoundtripsEncodedBackup() throws {
        let s = song("A")
        let original = backup([s], [version(s.id, file: "a.m4a")])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoded = try LibraryBackup.decode(from: encoder.encode(original))
        XCTAssertEqual(decoded.songs, original.songs)
        XCTAssertEqual(decoded.versions, original.versions)
    }

    func testDecodeRejectsGarbageForeignAndNewerFiles() throws {
        XCTAssertThrowsError(try LibraryBackup.decode(from: Data("nope".utf8))) { XCTAssertEqual($0 as? BackupError, .unreadable) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var foreign = backup([], [])
        foreign.app = "Other"
        XCTAssertThrowsError(try LibraryBackup.decode(from: encoder.encode(foreign))) { XCTAssertEqual($0 as? BackupError, .notAnEraBackup) }
        var newer = backup([], [])
        newer.formatVersion = 99
        XCTAssertThrowsError(try LibraryBackup.decode(from: encoder.encode(newer))) { XCTAssertEqual($0 as? BackupError, .newerFormat(99)) }
    }

    func testPlanKeepsOnlySongsWhoseAudioStillExists() {
        let a = song("A"), b = song("B")
        let state = LibraryState(audioFileNames: ["a.m4a"])
        let plan = RestorePlanner.plan(backup([a, b], [version(a.id, file: "a.m4a"), version(b.id, file: "b.m4a")]), against: state)
        XCTAssertEqual(plan.songs.map(\.song.title), ["A"])
        XCTAssertEqual(plan.skippedMissingAudio, 1)
        XCTAssertFalse(plan.resolvableSongIDs.contains(b.id))
    }

    func testPlanSkipsExistingSongsVersionsAndHashes() {
        let a = song("A"), b = song("B"), c = song("C")
        let shared = version(b.id, file: "b.m4a", hash: "same")
        let state = LibraryState(songIDs: [a.id], pcmHashes: ["same"], audioFileNames: ["a.m4a", "b.m4a", "c.m4a"])
        let plan = RestorePlanner.plan(backup([a, b, c], [version(a.id, file: "a.m4a"), shared, version(c.id, file: "c.m4a")]), against: state)
        XCTAssertEqual(plan.skippedExisting, 1)
        XCTAssertEqual(plan.songs.map(\.song.title), ["C"])
        XCTAssertTrue(plan.resolvableSongIDs.isSuperset(of: [a.id, c.id]))
    }

    func testPlanKeepsVersionOrderAndDropsDuplicateHashesInsideBackup() {
        let a = song("A")
        let v1 = version(a.id, file: "1.m4a", hash: "h1", sortIndex: 1)
        let v0 = version(a.id, file: "0.m4a", hash: "h0", sortIndex: 0)
        let dupe = version(a.id, file: "2.m4a", hash: "h0", sortIndex: 2)
        let state = LibraryState(audioFileNames: ["0.m4a", "1.m4a", "2.m4a"])
        let plan = RestorePlanner.plan(backup([a], [v1, dupe, v0]), against: state)
        XCTAssertEqual(plan.songs.first?.versions.map(\.fileName), ["0.m4a", "1.m4a"])
    }

    func testPlanAddsOnlyNewPacksAndPlaylists() {
        let pack = LibraryBackup.PackEntry(id: UUID(), name: "Demos", tagIDs: [], statusNames: [], confirmed: true)
        let known = LibraryBackup.PackEntry(id: UUID(), name: "SYNTH", tagIDs: [], statusNames: [], confirmed: true)
        let list = LibraryBackup.PlaylistEntry2(id: UUID(), name: "P", filterTagIDs: [], entries: [])
        let oldList = LibraryBackup.PlaylistEntry2(id: UUID(), name: "Old", filterTagIDs: [], entries: [])
        let state = LibraryState(packNames: ["synth"], playlistIDs: [oldList.id])
        let plan = RestorePlanner.plan(backup([], [], packs: [pack, known], playlists: [list, oldList]), against: state)
        XCTAssertEqual(plan.newPacks.map(\.name), ["Demos"])
        XCTAssertEqual(plan.newPlaylists.map(\.name), ["P"])
        XCTAssertFalse(plan.isEmpty)
    }
}

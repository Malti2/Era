import XCTest
@testable import Era

final class PlaylistM3UImportTests: XCTestCase {
    private let library: [PlaylistM3UImport.LibraryTrack] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Night Drive",
              artist: "Neon Coast", fileNames: ["night-drive.mp3"]),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Sketch Two (Demo)",
              artist: "Neon Coast", fileNames: ["sketch-two-v2.m4a", "sketch-two-v1.m4a"]),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, title: "Night Drive",
              artist: "Other Band", fileNames: ["other-night-drive.mp3"]),
    ]

    func testParseExtendedM3U() {
        let text = """
            #EXTM3U
            #EXTINF:233,Neon Coast - Night Drive
            /Music/neon-coast/night-drive.mp3
            #EXTINF:-1,Sketch Two
            sketch-two-v2.m4a
            """
        let entries = PlaylistM3UImport.parse(text)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0], M3UEntry(title: "Night Drive", artist: "Neon Coast", duration: 233, path: "/Music/neon-coast/night-drive.mp3"))
        XCTAssertEqual(entries[1].title, "Sketch Two")
        XCTAssertEqual(entries[1].duration, 0)
    }

    func testParsePlainM3UUsesFileNameAsTitle() {
        let entries = PlaylistM3UImport.parse("night-drive.mp3\nsketch-two-v2.m4a\n")
        XCTAssertEqual(entries.map(\.title), ["night-drive", "sketch-two-v2"])
        XCTAssertTrue(entries.allSatisfy { $0.artist.isEmpty })
    }

    func testParseSkipsCommentsAndBlankLinesAndDecodesPaths() {
        let text = "#EXTM3U\r\n#PLAYLIST:Roadtrip\r\n\r\nmy%20song.mp3\r\n# a comment\n"
        let entries = PlaylistM3UImport.parse(text)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].path, "my song.mp3")
        XCTAssertEqual(entries[0].title, "my song")
    }

    func testParseLabelWithoutDashIsTitleOnly() {
        let entries = PlaylistM3UImport.parse("#EXTINF:200,Just A Title\ntrack.mp3\n")
        XCTAssertEqual(entries[0].title, "Just A Title")
        XCTAssertTrue(entries[0].artist.isEmpty)
    }

    func testMatchByFileNameBeatsAmbiguousTitle() {
        let entries = PlaylistM3UImport.parse("#EXTINF:233,Somebody - Night Drive\nother-night-drive.mp3\n")
        let result = PlaylistM3UImport.match(entries, against: library)
        XCTAssertEqual(result.matched, [library[2].id])
        XCTAssertTrue(result.unmatched.isEmpty)
    }

    func testMatchByBaseNameWithoutExtension() {
        let entries = [M3UEntry(title: "Night Drive", artist: "", duration: 0, path: "night-drive.flac")]
        let result = PlaylistM3UImport.match(entries, against: library)
        XCTAssertEqual(result.matched, [library[0].id])
    }

    func testMatchByTitleAndArtistWithDemoSuffix() {
        let entries = [M3UEntry(title: "Sketch Two", artist: "Neon Coast", duration: 0, path: "somewhere-else.mp3")]
        let result = PlaylistM3UImport.match(entries, against: library)
        XCTAssertEqual(result.matched, [library[1].id])
    }

    func testMatchTitleOnlyNeedsUniqueTitle() {
        // "Night Drive" gibt es zweimal -> kein Treffer, kein Raten.
        let ambiguous = [M3UEntry(title: "Night Drive", artist: "", duration: 0, path: "unknown.mp3")]
        XCTAssertTrue(PlaylistM3UImport.match(ambiguous, against: library).matched.isEmpty)
        XCTAssertEqual(PlaylistM3UImport.match(ambiguous, against: library).unmatched.count, 1)
        let unique = [M3UEntry(title: "Sketch Two (Demo)", artist: "", duration: 0, path: "unknown.mp3")]
        XCTAssertEqual(PlaylistM3UImport.match(unique, against: library).matched, [library[1].id])
    }

    func testMatchDeduplicatesAndKeepsOrder() {
        let entries = PlaylistM3UImport.parse("night-drive.mp3\nsketch-two-v2.m4a\nnight-drive.mp3\nmissing.mp3\n")
        let result = PlaylistM3UImport.match(entries, against: library)
        XCTAssertEqual(result.matched, [library[0].id, library[1].id])
        XCTAssertEqual(result.unmatched.map(\.title), ["missing"])
    }

    func testMatchIsCaseInsensitive() {
        let entries = [M3UEntry(title: "NIGHT DRIVE", artist: "NEON COAST", duration: 0, path: "NIGHT-DRIVE.MP3")]
        XCTAssertEqual(PlaylistM3UImport.match(entries, against: library).matched, [library[0].id])
    }
}

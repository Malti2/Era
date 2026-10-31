import XCTest
@testable import Era

final class VersionMarkersTests: XCTestCase {
    func testRoundTripKeepsOrderAndLabels() {
        let list = [VersionMarker(time: 40, label: "Drop"), VersionMarker(time: 5.5, label: "Hook")]
        let decoded = VersionMarkers.decode(VersionMarkers.encode(list))
        XCTAssertEqual(decoded.map(\.label), ["Hook", "Drop"])
        XCTAssertEqual(decoded.map(\.id), [list[1].id, list[0].id])
    }

    func testDecodeToleratesGarbageAndEmpty() {
        XCTAssertEqual(VersionMarkers.decode(nil), [])
        XCTAssertEqual(VersionMarkers.decode(""), [])
        XCTAssertEqual(VersionMarkers.decode("not json"), [])
        XCTAssertEqual(VersionMarkers.encode([]), "")
    }

    func testDecodeDropsNegativeTimes() {
        let json = VersionMarkers.encode([VersionMarker(time: 3, label: "ok")])
            .replacingOccurrences(of: "\"time\":3", with: "\"time\":-3")
        XCTAssertEqual(VersionMarkers.decode(json), [])
    }

    func testAddingSortsAndTrimsLabel() throws {
        var markers: [VersionMarker] = []
        markers = try XCTUnwrap(VersionMarkers.adding(at: 60, label: "  Bridge  ", to: markers)).markers
        let second = try XCTUnwrap(VersionMarkers.adding(at: 12.34, to: markers))
        XCTAssertTrue(second.isNew)
        XCTAssertEqual(second.markers.map(\.time), [12.3, 60])
        XCTAssertEqual(second.markers.last?.label, "Bridge")
    }

    func testAddingNearExistingMarkerDoesNotDuplicate() throws {
        let first = try XCTUnwrap(VersionMarkers.adding(at: 30, label: "A", to: []))
        let again = try XCTUnwrap(VersionMarkers.adding(at: 30.6, label: "B", to: first.markers))
        XCTAssertFalse(again.isNew)
        XCTAssertEqual(again.markers.count, 1)
        XCTAssertEqual(again.marker.id, first.marker.id)
    }

    func testAddingRejectsInvalidTimesAndClampsToDuration() throws {
        XCTAssertNil(VersionMarkers.adding(at: -1, to: []))
        XCTAssertNil(VersionMarkers.adding(at: .nan, to: []))
        let clamped = try XCTUnwrap(VersionMarkers.adding(at: 500, duration: 200, to: []))
        XCTAssertEqual(clamped.marker.time, 200)
    }

    func testAddingRespectsMaximum() {
        let full = (0..<VersionMarkers.maxCount).map { VersionMarker(time: Double($0) * 2, label: "") }
        XCTAssertNil(VersionMarkers.adding(at: 9999, to: full))
    }

    func testLabelLengthIsLimited() {
        XCTAssertEqual(VersionMarkers.cleaned(label: String(repeating: "x", count: 200)).count, VersionMarkers.maxLabelLength)
    }

    func testRemoveAndRename() {
        let a = VersionMarker(time: 1, label: "A"), b = VersionMarker(time: 9, label: "B")
        XCTAssertEqual(VersionMarkers.removing(a.id, from: [a, b]), [b])
        let renamed = VersionMarkers.renaming(b.id, to: " Chorus ", in: [a, b])
        XCTAssertEqual(renamed.map(\.label), ["A", "Chorus"])
    }

    func testNextAndPrevious() {
        let m = [VersionMarker(time: 10, label: "a"), VersionMarker(time: 50, label: "b"), VersionMarker(time: 90, label: "c")]
        XCTAssertEqual(VersionMarkers.next(after: 0, in: m)?.label, "a")
        XCTAssertEqual(VersionMarkers.next(after: 10, in: m)?.label, "b")
        XCTAssertNil(VersionMarkers.next(after: 90, in: m))
        XCTAssertEqual(VersionMarkers.previous(before: 100, in: m)?.label, "c")
        // knapp hinter einem Marker springt "zurueck" zum davor, nicht auf der Stelle
        XCTAssertEqual(VersionMarkers.previous(before: 50.5, in: m)?.label, "a")
        XCTAssertNil(VersionMarkers.previous(before: 5, in: m))
    }

    func testCurrentMarkerWindow() {
        let m = [VersionMarker(time: 20, label: "x")]
        XCTAssertEqual(VersionMarkers.current(at: 20.4, in: m)?.label, "x")
        XCTAssertNil(VersionMarkers.current(at: 25, in: m))
        XCTAssertNil(VersionMarkers.current(at: 10, in: m))
    }

    func testFractions() {
        let m = [VersionMarker(time: 25, label: ""), VersionMarker(time: 400, label: "")]
        XCTAssertEqual(VersionMarkers.fractions(of: m, duration: 100), [0.25, 1])
        XCTAssertEqual(VersionMarkers.fractions(of: m, duration: 0), [])
    }

    func testMergedNotes() {
        XCTAssertEqual(VersionMarkers.mergedNotes("", "b"), "b")
        XCTAssertEqual(VersionMarkers.mergedNotes("a", " "), "a")
        XCTAssertEqual(VersionMarkers.mergedNotes("a", "b"), "a\n\nb")
        XCTAssertEqual(VersionMarkers.mergedNotes("a b", "b"), "a b")
    }
}

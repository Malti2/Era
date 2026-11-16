import XCTest
@testable import Era

final class EraTimelineTests: XCTestCase {
    private func song(_ era: String, _ year: Int? = nil, _ seconds: Double = 100, _ statuses: [String] = []) -> EraSong {
        EraSong(era: era, year: year, duration: seconds, statuses: statuses)
    }

    func testGroupsAreChronologicalWithUnknownLast() {
        let groups = EraTimeline.groups(of: [
            song("Pop", 2021), song("", 2010), song("Synth", 2018), song("Synth", 2019), song("Zeta"), song("Alpha"),
        ])
        XCTAssertEqual(groups.map(\.name), ["Synth", "Pop", "Alpha", "Zeta", ""])
        XCTAssertEqual(groups.first?.yearText, "2018–2019")
        XCTAssertEqual(groups[1].yearText, "2021")
        XCTAssertNil(groups[2].yearText)
    }

    func testSameEraInDifferentSpellingIsOneGroup() {
        let groups = EraTimeline.groups(of: [song("Café Era"), song(" cafe era "), song("Other")])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first { $0.name == "Café Era" }?.ids.count, 2)
    }

    func testDurationAndStatusMix() {
        let group = EraTimeline.groups(of: [
            song("E", 2020, 60, ["Demo"]), song("E", 2021, 90, ["Demo", "Leak"]), song("E", nil, 30, ["released"]),
        ])[0]
        XCTAssertEqual(group.duration, 180)
        XCTAssertEqual(group.statusCounts.map(\.name), ["Demo", "Leak", "released"])
        XCTAssertEqual(group.statusCounts.map(\.count), [2, 1, 1])
        XCTAssertEqual(group.years, 2020...2021)
    }

    func testUsefulOnlyWithAtLeastOneEra() {
        XCTAssertFalse(EraTimeline.isUseful([song(""), song("  ")]))
        XCTAssertTrue(EraTimeline.isUseful([song(""), song("Pop")]))
        XCTAssertFalse(EraTimeline.isUseful([]))
    }

    func testStatusSegmentsAreFractionsOfTheMix() {
        let group = EraTimeline.groups(of: [
            song("E", 2020, 60, ["Demo"]), song("E", 2021, 90, ["Demo", "Leak"]), song("E", nil, 30, ["released"]),
        ])[0]
        XCTAssertEqual(group.statusSegments.map(\.name), ["Demo", "Leak", "released"])
        XCTAssertEqual(group.statusSegments.map(\.count), [2, 1, 1])
        let fractions = group.statusSegments.map(\.fraction)
        XCTAssertEqual(fractions.count, 3)
        zip(fractions, [0.5, 0.25, 0.25]).forEach { XCTAssertEqual($0, $1, accuracy: 0.0001) }
        XCTAssertEqual(fractions.reduce(0, +), 1, accuracy: 0.0001)
    }

    func testStatusSegmentsAreEmptyWithoutSongs() {
        XCTAssertTrue(EraGroup(name: "E", ids: [], years: nil, duration: 0, statusCounts: []).statusSegments.isEmpty)
    }

    func testEmptyInput() {
        XCTAssertTrue(EraTimeline.groups(of: []).isEmpty)
    }
}

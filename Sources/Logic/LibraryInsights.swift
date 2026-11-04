import Foundation

// Bibliotheks-Uebersicht: Zahlen, Status-Verteilung, Eras und Zuwachs pro Jahr - reine Logik auf Snapshots.

struct InsightSong: Equatable {
    var statuses: [String]
    var era: String
    var dateAdded: Date
    var versionCount: Int
    var duration: Double
    var playCount: Int
    var isFavorite: Bool
    var hasNotes: Bool
    var markerCount: Int
}

struct LibraryInsights: Equatable {
    struct Entry: Equatable, Identifiable {
        var name: String
        var count: Int
        var id: String { name }
    }
    struct YearCount: Equatable, Identifiable {
        var year: Int
        var count: Int
        var id: Int { year }
    }

    var songs = 0
    var versions = 0
    var totalSeconds = 0.0
    var favorites = 0
    var neverPlayed = 0
    var withNotes = 0
    var markers = 0
    /// Songs mit mehr als einer Version
    var multiVersion = 0
    /// Status -> Anzahl, haeufigste zuerst; Songs ohne Status zaehlen unter `unknownName`
    var statuses: [Entry] = []
    var eras: [Entry] = []
    /// Neu hinzugefuegte Songs pro Jahr, aelteste zuerst, ohne Luecken
    var addedPerYear: [YearCount] = []

    var isEmpty: Bool { songs == 0 }
    var averageVersions: Double { songs > 0 ? Double(versions) / Double(songs) : 0 }

    static func make(from list: [InsightSong], unknownName: String = "Unknown", eraLimit: Int = 5,
                     calendar: Calendar = .current) -> LibraryInsights {
        var result = LibraryInsights()
        var statusCounts: [String: Int] = [:]
        var eraCounts: [String: Int] = [:]
        var yearCounts: [Int: Int] = [:]
        for song in list {
            result.songs += 1
            result.versions += song.versionCount
            result.totalSeconds += song.duration
            if song.isFavorite { result.favorites += 1 }
            if song.playCount == 0 { result.neverPlayed += 1 }
            if song.hasNotes { result.withNotes += 1 }
            result.markers += song.markerCount
            if song.versionCount > 1 { result.multiVersion += 1 }
            let statuses = song.statuses.isEmpty ? [unknownName] : song.statuses
            for status in Set(statuses) { statusCounts[status, default: 0] += 1 }
            let era = song.era.trimmingCharacters(in: .whitespacesAndNewlines)
            if !era.isEmpty { eraCounts[era, default: 0] += 1 }
            yearCounts[calendar.component(.year, from: song.dateAdded), default: 0] += 1
        }
        result.statuses = sorted(statusCounts)
        result.eras = Array(sorted(eraCounts).prefix(eraLimit))
        if let first = yearCounts.keys.min(), let last = yearCounts.keys.max() {
            result.addedPerYear = (first...last).map { YearCount(year: $0, count: yearCounts[$0] ?? 0) }
        }
        return result
    }

    private static func sorted(_ counts: [String: Int]) -> [Entry] {
        counts.map { Entry(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

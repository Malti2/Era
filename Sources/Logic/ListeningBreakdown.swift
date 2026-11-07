import Foundation

// Wohin geht die Hoerzeit? Verteilung der Wiedergaben nach Status, Era, Tag oder Album.
// Reine Logik: Wiedergaben tragen die Song-ID, die Song-Eigenschaften kommen als Snapshot.

struct ListeningSong: Equatable {
    var album: String
    var era: String
    var tags: [String]
    var statuses: [String]

    init(album: String = "", era: String = "", tags: [String] = [], statuses: [String] = []) {
        self.album = album
        self.era = era
        self.tags = tags
        self.statuses = statuses
    }
}

enum ListeningDimension: String, CaseIterable, Identifiable {
    case status, era, tag, album
    var id: String { rawValue }
}

struct ListeningShare: Identifiable, Equatable {
    var name: String
    var plays: Int
    var seconds: Double
    /// Anteil an der gesamten (zuordenbaren) Hoerzeit, 0...1. Songs mit mehreren Tags zaehlen bei jedem.
    var share: Double
    var id: String { name }
}

enum ListeningBreakdown {
    /// Gruppen nach Hoerzeit absteigend. Wiedergaben ohne bekannten Song (geloescht) werden ignoriert.
    /// `unknownName` steht fuer Songs ohne Wert in der Dimension (z.B. ohne Era).
    static func make(_ dimension: ListeningDimension, records: [PlayRecord], songs: [UUID: ListeningSong],
                     limit: Int = 6, unknownName: String = "?") -> [ListeningShare] {
        var groups: [String: (name: String, plays: Int, seconds: Double)] = [:]
        var total = 0.0
        var totalPlays = 0
        for record in records {
            guard let id = record.songID, let song = songs[id] else { continue }
            total += record.seconds
            totalPlays += 1
            for name in names(for: dimension, of: song, unknownName: unknownName) {
                let key = SongSearch.fold(name)
                var entry = groups[key] ?? (name, 0, 0)
                entry.plays += 1
                entry.seconds += record.seconds
                groups[key] = entry
            }
        }
        let useSeconds = total > 0
        let list = groups.values.map { entry -> ListeningShare in
            let share = useSeconds ? entry.seconds / total : (totalPlays > 0 ? Double(entry.plays) / Double(totalPlays) : 0)
            return ListeningShare(name: entry.name, plays: entry.plays, seconds: entry.seconds, share: min(1, share))
        }
        return Array(list.sorted {
            if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
            if $0.plays != $1.plays { return $0.plays > $1.plays }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.prefix(limit))
    }

    /// Dimensionen, in denen die Songs ueberhaupt etwas unterscheiden (sonst waere die Auswahl leer/langweilig).
    static func availableDimensions(songs: [ListeningSong]) -> [ListeningDimension] {
        ListeningDimension.allCases.filter { dimension in
            let distinct = Set(songs.flatMap { names(for: dimension, of: $0, unknownName: "") }.filter { !$0.isEmpty }.map(SongSearch.fold))
            return !distinct.isEmpty
        }
    }

    private static func names(for dimension: ListeningDimension, of song: ListeningSong, unknownName: String) -> [String] {
        func clean(_ values: [String]) -> [String] {
            let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return trimmed.isEmpty ? [unknownName] : Array(Set(trimmed))
        }
        switch dimension {
        case .status: return clean(song.statuses)
        case .era: return clean([song.era])
        case .tag: return clean(song.tags)
        case .album: return clean([song.album])
        }
    }
}

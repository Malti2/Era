import Foundation

// Playlist-Werkzeuge als reine Logik: dauerhaft umsortieren und als Text teilen.

struct PlaylistRow: Equatable {
    var id: UUID
    var title: String
    var artist: String
    var dateAdded: Date
    var duration: Double

    init(id: UUID = UUID(), title: String, artist: String = "", dateAdded: Date = Date(timeIntervalSince1970: 0), duration: Double = 0) {
        self.id = id
        self.title = title
        self.artist = artist
        self.dateAdded = dateAdded
        self.duration = duration
    }
}

enum PlaylistSortOrder: String, CaseIterable, Identifiable {
    case title, artist, newest, longest, reverse
    var id: String { rawValue }

    /// Ids in neuer Reihenfolge. Stabil: Gleiche Werte behalten ihre bisherige Reihenfolge.
    func ordered(_ rows: [PlaylistRow]) -> [UUID] {
        if self == .reverse { return rows.reversed().map(\.id) }
        let sorted = rows.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            let order: ComparisonResult
            switch self {
            case .title: order = a.title.localizedStandardCompare(b.title)
            case .artist:
                // Eintraege ohne Artist ans Ende
                if a.artist.isEmpty != b.artist.isEmpty { return b.artist.isEmpty }
                order = a.artist.localizedStandardCompare(b.artist)
            case .newest: order = a.dateAdded == b.dateAdded ? .orderedSame : (a.dateAdded > b.dateAdded ? .orderedAscending : .orderedDescending)
            case .longest: order = a.duration == b.duration ? .orderedSame : (a.duration > b.duration ? .orderedAscending : .orderedDescending)
            case .reverse: order = .orderedSame
            }
            return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
        }
        return sorted.map { $0.element.id }
    }
}

enum PlaylistTextExport {
    struct Item: Equatable {
        var title: String
        var artist: String
        var duration: Double
    }

    /// Nummerierte Liste zum Teilen ("1. Titel – Artist (3:21)"); `header` ist die fertig lokalisierte Titelzeile.
    static func text(header: String, items: [Item]) -> String {
        var lines = [header, ""]
        for (index, item) in items.enumerated() {
            var line = "\(index + 1). \(item.title)"
            if !item.artist.isEmpty { line += " – \(item.artist)" }
            if item.duration > 0 { line += " (\(clock(item.duration)))" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

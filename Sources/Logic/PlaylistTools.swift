import Foundation

// Playlist-Werkzeuge als reine Logik: dauerhaft umsortieren und als Text teilen.

struct PlaylistRow: Equatable {
    var id: UUID
    var title: String
    var artist: String
    var dateAdded: Date
    var duration: Double
    var rating: Int

    init(id: UUID = UUID(), title: String, artist: String = "", dateAdded: Date = Date(timeIntervalSince1970: 0), duration: Double = 0, rating: Int = 0) {
        self.id = id
        self.title = title
        self.artist = artist
        self.dateAdded = dateAdded
        self.duration = duration
        self.rating = rating
    }
}

enum PlaylistSortOrder: String, CaseIterable, Identifiable {
    case title, artist, newest, longest, rating, reverse
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
            case .rating: order = a.rating == b.rating ? .orderedSame : (a.rating > b.rating ? .orderedAscending : .orderedDescending)
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
        /// Dateiname im App-Container (fuer M3U); leer = nur Titel bekannt.
        var fileName: String = ""
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

/// M3U-Export: `#EXTM3U` + je Track `#EXTINF:<sekunden>,Artist - Titel` und Dateiname.
/// Andere Player koennen die Liste so direkt importieren, wenn die Dateien daneben liegen.
enum PlaylistM3UExport {
    static func m3u(items: [PlaylistTextExport.Item]) -> String {
        var lines = ["#EXTM3U"]
        for item in items {
            let seconds = item.duration > 0 ? Int(item.duration.rounded()) : -1
            let label = item.artist.isEmpty ? item.title : "\(item.artist) - \(item.title)"
            lines.append("#EXTINF:\(seconds),\(label)")
            lines.append(item.fileName.isEmpty ? item.title : item.fileName)
        }
        return lines.joined(separator: "\n")
    }
}

import Foundation

// Sortierung und Gruppierung der Bibliothek als reine Logik (testbar ohne SwiftData).

struct SortRow: Equatable {
    var id: UUID
    var title: String
    var artist: String
    var year: Int?
    var playCount: Int
    var dateAdded: Date
    var duration: Double

    init(id: UUID = UUID(), title: String, artist: String = "", year: Int? = nil, playCount: Int = 0,
         dateAdded: Date = Date(timeIntervalSince1970: 0), duration: Double = 0) {
        self.id = id
        self.title = title
        self.artist = artist
        self.year = year
        self.playCount = playCount
        self.dateAdded = dateAdded
        self.duration = duration
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, title, artist, year, mostPlayed, longest
    var id: String { rawValue }

    /// Ids in der Reihenfolge dieser Sortierung; Gleichstaende fallen auf Titel zurueck.
    func ordered(_ rows: [SortRow]) -> [UUID] {
        func byTitle(_ a: SortRow, _ b: SortRow) -> Bool {
            let order = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? a.dateAdded > b.dateAdded : order == .orderedAscending
        }
        let sorted: [SortRow]
        switch self {
        case .recent:
            sorted = rows.sorted { $0.dateAdded != $1.dateAdded ? $0.dateAdded > $1.dateAdded : byTitle($0, $1) }
        case .title:
            sorted = rows.sorted(by: byTitle)
        case .artist:
            sorted = rows.sorted { a, b in
                // Songs ohne Artist ans Ende
                if a.artist.isEmpty != b.artist.isEmpty { return b.artist.isEmpty }
                let order = a.artist.localizedStandardCompare(b.artist)
                return order == .orderedSame ? byTitle(a, b) : order == .orderedAscending
            }
        case .year:
            sorted = rows.sorted { a, b in
                // Neueste zuerst, ohne Jahr ans Ende
                switch (a.year, b.year) {
                case let (x?, y?): return x != y ? x > y : byTitle(a, b)
                case (nil, nil): return byTitle(a, b)
                case (_?, nil): return true
                case (nil, _?): return false
                }
            }
        case .mostPlayed:
            sorted = rows.sorted { $0.playCount != $1.playCount ? $0.playCount > $1.playCount : byTitle($0, $1) }
        case .longest:
            sorted = rows.sorted { $0.duration != $1.duration ? $0.duration > $1.duration : byTitle($0, $1) }
        }
        return sorted.map(\.id)
    }
}

enum LibraryGrouping {
    struct Group: Equatable, Identifiable {
        var id: String { SongSearch.fold(name) }
        /// Leer = unbekannt (Artist/Album fehlt); die UI setzt dafuer ihren eigenen Text ein.
        var name: String
        var ids: [UUID]
    }

    /// Gruppiert nach Name (Gross-/Kleinschreibung und Akzente egal), alphabetisch
    /// nach "Finder"-Regeln; die Gruppe ohne Namen kommt zuletzt.
    static func groups(of items: [(id: UUID, name: String)]) -> [Group] {
        var order: [String] = []
        var buckets: [String: Group] = [:]
        for item in items {
            let display = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = SongSearch.fold(display)
            if buckets[key] == nil {
                buckets[key] = Group(name: display, ids: [])
                order.append(key)
            }
            buckets[key]?.ids.append(item.id)
        }
        return order.compactMap { buckets[$0] }.sorted { a, b in
            if a.name.isEmpty != b.name.isEmpty { return b.name.isEmpty }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

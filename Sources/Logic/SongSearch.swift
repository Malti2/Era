import Foundation

// Suche ueber die lokale Bibliothek: mehrere Begriffe (UND), unempfindlich gegen
// Gross-/Kleinschreibung und Akzente, Treffer nach Qualitaet sortiert, plus
// Filter-Operatoren wie `tag:demo`, `status:leak`, `year:2018-2020`, `fav`.
// Reine Foundation-Logik auf Snapshots, damit sie ohne SwiftData testbar ist.

struct SearchableSong: Equatable {
    var id: UUID
    var title: String
    var artist: String
    var album: String
    var era: String
    var year: Int?
    var tags: [String]
    var statuses: [String]
    var versionNames: [String]
    var isFavorite: Bool
    var playCount: Int
    /// Freie Notiz am Song plus Marker-Beschriftungen - nur ein schwacher Treffer, aber so findet man "das mit dem Gitarrenriff".
    var notes: String
    var markerLabels: [String]

    init(id: UUID = UUID(), title: String, artist: String = "", album: String = "", era: String = "",
         year: Int? = nil, tags: [String] = [], statuses: [String] = [], versionNames: [String] = [],
         isFavorite: Bool = false, playCount: Int = 0, notes: String = "", markerLabels: [String] = []) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.era = era
        self.year = year
        self.tags = tags
        self.statuses = statuses
        self.versionNames = versionNames
        self.isFavorite = isFavorite
        self.playCount = playCount
        self.notes = notes
        self.markerLabels = markerLabels
    }
}

enum SearchField: Hashable {
    case title, artist, album, era, tag, status, version, note
}

struct SearchHit: Equatable {
    let id: UUID
    let score: Int
    let matchedFields: Set<SearchField>
}

enum SearchFilter: Equatable {
    case tag(String)
    case status(String)
    case version(String)
    case artist(String)
    case album(String)
    case year(ClosedRange<Int>)
    case favorite
}

struct SongSearchQuery: Equatable {
    var terms: [String] = []
    var filters: [SearchFilter] = []

    var isEmpty: Bool { terms.isEmpty && filters.isEmpty }

    /// Zerlegt die Eingabe in Begriffe und Filter. Anfuehrungszeichen halten
    /// Phrasen zusammen ("blue hour", tag:"late night").
    init(_ raw: String) {
        for token in SongSearchQuery.tokenize(raw) {
            if let filter = SongSearchQuery.filter(from: token) {
                filters.append(filter)
            } else {
                let term = SongSearch.fold(token.replacingOccurrences(of: "\"", with: ""))
                if !term.isEmpty { terms.append(term) }
            }
        }
    }

    private static func tokenize(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for ch in raw {
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
            } else if ch.isWhitespace && !inQuotes {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func filter(from token: String) -> SearchFilter? {
        let lowered = token.lowercased()
        if lowered == "fav" || lowered == "favorite" || lowered == "is:fav" || lowered == "is:favorite" { return .favorite }
        guard let colon = token.firstIndex(of: ":") else { return nil }
        let key = token[..<colon].lowercased()
        let value = SongSearch.fold(String(token[token.index(after: colon)...]).replacingOccurrences(of: "\"", with: ""))
        guard !value.isEmpty else { return nil }
        switch key {
        case "tag": return .tag(value)
        case "status": return .status(value)
        case "version", "v": return .version(value)
        case "artist": return .artist(value)
        case "album": return .album(value)
        case "year": return yearRange(value).map(SearchFilter.year)
        default: return nil
        }
    }

    private static func yearRange(_ value: String) -> ClosedRange<Int>? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1, let year = Int(parts[0]) { return year...year }
        if parts.count == 2, let low = Int(parts[0]), let high = Int(parts[1]) { return min(low, high)...max(low, high) }
        return nil
    }
}

enum SongSearch {
    /// Kleinschreibung ohne Akzente - gemeinsame Basis fuer jeden Vergleich.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Treffer fuer die Eingabe, beste zuerst. Leere Eingabe liefert nichts.
    static func search(_ raw: String, in songs: [SearchableSong]) -> [SearchHit] {
        let query = SongSearchQuery(raw)
        guard !query.isEmpty else { return [] }
        var hits: [(hit: SearchHit, song: SearchableSong)] = []
        for song in songs {
            guard let hit = match(song, query: query) else { continue }
            hits.append((hit, song))
        }
        hits.sort { lhs, rhs in
            if lhs.hit.score != rhs.hit.score { return lhs.hit.score > rhs.hit.score }
            if lhs.song.playCount != rhs.song.playCount { return lhs.song.playCount > rhs.song.playCount }
            return lhs.song.title.localizedStandardCompare(rhs.song.title) == .orderedAscending
        }
        return hits.map(\.hit)
    }

    static func match(_ song: SearchableSong, query: SongSearchQuery) -> SearchHit? {
        var fields = Set<SearchField>()
        var score = 0
        for filter in query.filters {
            guard let matched = apply(filter, to: song) else { return nil }
            fields.formUnion(matched)
            score += 5
        }
        let title = fold(song.title), artist = fold(song.artist), album = fold(song.album), era = fold(song.era)
        let tags = song.tags.map(fold), statuses = song.statuses.map(fold), versions = song.versionNames.map(fold)
        let notes = fold(song.notes), markerLabels = song.markerLabels.map(fold)
        for term in query.terms {
            var best = 0
            var termFields = Set<SearchField>()
            func consider(_ value: String, field: SearchField, exact: Int, prefix: Int, word: Int, contains: Int) {
                guard !value.isEmpty else { return }
                let points: Int
                if value == term { points = exact }
                else if value.hasPrefix(term) { points = prefix }
                else if value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(term) }) { points = word }
                else if value.contains(term) { points = contains }
                else { return }
                termFields.insert(field)
                best = max(best, points)
            }
            consider(title, field: .title, exact: 100, prefix: 80, word: 60, contains: 40)
            consider(artist, field: .artist, exact: 50, prefix: 40, word: 32, contains: 25)
            consider(album, field: .album, exact: 30, prefix: 24, word: 20, contains: 14)
            consider(era, field: .era, exact: 22, prefix: 18, word: 15, contains: 10)
            for tag in tags { consider(tag, field: .tag, exact: 28, prefix: 22, word: 16, contains: 10) }
            for status in statuses { consider(status, field: .status, exact: 28, prefix: 22, word: 16, contains: 10) }
            for version in versions { consider(version, field: .version, exact: 20, prefix: 14, word: 10, contains: 6) }
            consider(notes, field: .note, exact: 12, prefix: 10, word: 9, contains: 5)
            for label in markerLabels { consider(label, field: .note, exact: 12, prefix: 10, word: 9, contains: 5) }
            if let year = song.year, String(year) == term { best = max(best, 26) }
            guard best > 0 else { return nil }
            score += best
            fields.formUnion(termFields)
        }
        if song.isFavorite { score += 2 }
        return SearchHit(id: song.id, score: score, matchedFields: fields)
    }

    /// nil = Filter passt nicht; sonst die Felder, in denen er getroffen hat.
    private static func apply(_ filter: SearchFilter, to song: SearchableSong) -> Set<SearchField>? {
        switch filter {
        case .favorite:
            return song.isFavorite ? [] : nil
        case .year(let range):
            guard let year = song.year, range.contains(year) else { return nil }
            return []
        case .tag(let value):
            return song.tags.contains { fold($0).contains(value) } ? [.tag] : nil
        case .status(let value):
            return song.statuses.contains { fold($0).hasPrefix(value) } ? [.status] : nil
        case .version(let value):
            return song.versionNames.contains { fold($0).contains(value) } ? [.version] : nil
        case .artist(let value):
            return fold(song.artist).contains(value) ? [.artist] : nil
        case .album(let value):
            return fold(song.album).contains(value) ? [.album] : nil
        }
    }
}

// MARK: - Vorschlaege fuer die leere Suche

struct SearchSuggestion: Equatable, Identifiable {
    let query: String
    let label: String
    let count: Int
    var id: String { query }
}

enum SearchSuggestions {
    /// Haeufigste Stati und Tags als antippbare Filter (`status:Leak`, `tag:demo`).
    static func make(from songs: [SearchableSong], limit: Int = 8) -> [SearchSuggestion] {
        func count(_ keyPath: KeyPath<SearchableSong, [String]>) -> [(String, Int)] {
            var counts: [String: (name: String, n: Int)] = [:]
            for song in songs {
                for name in Set(song[keyPath: keyPath]) where !name.isEmpty {
                    let key = SongSearch.fold(name)
                    counts[key] = (counts[key]?.name ?? name, (counts[key]?.n ?? 0) + 1)
                }
            }
            return counts.values.sorted { $0.n != $1.n ? $0.n > $1.n : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { ($0.name, $0.n) }
        }
        func quoted(_ name: String) -> String { name.contains(" ") ? "\"\(name)\"" : name }
        let statuses = count(\.statuses).prefix(4).map {
            SearchSuggestion(query: "status:\(quoted($0.0))", label: $0.0, count: $0.1)
        }
        let tags = count(\.tags).prefix(max(0, limit - statuses.count)).map {
            SearchSuggestion(query: "tag:\(quoted($0.0))", label: "#\($0.0)", count: $0.1)
        }
        return Array((statuses + tags).prefix(limit))
    }
}

// MARK: - Zuletzt gesucht

enum RecentSearches {
    static let limit = 8

    /// Neueste zuerst, ohne Duplikate (Gross-/Kleinschreibung egal), begrenzt.
    static func adding(_ query: String, to existing: [String]) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return existing }
        let key = SongSearch.fold(trimmed)
        var result = existing.filter { SongSearch.fold($0) != key }
        result.insert(trimmed, at: 0)
        return Array(result.prefix(limit))
    }
}

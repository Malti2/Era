import Foundation

// Zusaetzliche Home-Regale als reine Logik: Vergessenes und Wiederentdeckenswertes.

struct ShelfSong: Equatable {
    var id: UUID
    var playCount: Int
    var lastPlayedAt: Date?
    var dateAdded: Date
    var isFavorite: Bool
    var rating: Int

    init(id: UUID = UUID(), playCount: Int = 0, lastPlayedAt: Date? = nil,
         dateAdded: Date = Date(timeIntervalSince1970: 0), isFavorite: Bool = false, rating: Int = 0) {
        self.id = id
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.dateAdded = dateAdded
        self.isFavorite = isFavorite
        self.rating = rating
    }
}

enum HomeShelves {
    /// Die am besten bewerteten Songs (ab `SongRating.topRatedMinimum` Sternen), bei Gleichstand die oefter gespielten.
    static func topRated(_ songs: [ShelfSong], limit: Int = 20) -> [UUID] {
        songs
            .filter { $0.rating >= SongRating.topRatedMinimum }
            .sorted { lhs, rhs in
                if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
                if lhs.playCount != rhs.playCount { return lhs.playCount > rhs.playCount }
                return lhs.dateAdded > rhs.dateAdded
            }
            .prefix(limit)
            .map(\.id)
    }

    /// Nie gespielte Songs, die am laengsten ungehoert in der Bibliothek liegen zuerst.
    /// Songs, die gerade erst importiert wurden (`graceDays`), zaehlen noch nicht als vergessen.
    static func neverPlayed(_ songs: [ShelfSong], now: Date = Date(), graceDays: Int = 3, limit: Int = 20) -> [UUID] {
        let cutoff = now.addingTimeInterval(-Double(graceDays) * 86_400)
        return songs
            .filter { $0.playCount == 0 && $0.lastPlayedAt == nil && $0.dateAdded <= cutoff }
            .sorted { $0.dateAdded < $1.dateAdded }
            .prefix(limit)
            .map(\.id)
    }

    /// Frueher gespielte Songs, die seit `minDays` Tagen ruhen. Favoriten und oft gespielte zuerst.
    static func rediscover(_ songs: [ShelfSong], now: Date = Date(), minDays: Int = 30, limit: Int = 20) -> [UUID] {
        let cutoff = now.addingTimeInterval(-Double(minDays) * 86_400)
        return songs
            .filter { song in
                guard let last = song.lastPlayedAt else { return false }
                return last <= cutoff
            }
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                if lhs.playCount != rhs.playCount { return lhs.playCount > rhs.playCount }
                return (lhs.lastPlayedAt ?? .distantPast) < (rhs.lastPlayedAt ?? .distantPast)
            }
            .prefix(limit)
            .map(\.id)
    }

    struct Throwback: Equatable {
        var yearsAgo: Int
        var ids: [UUID]
    }

    /// Songs, die vor 1, 2, ... Jahren um diese Jahreszeit (+-`windowDays` Tage) in die Bibliothek kamen.
    /// Das juengste Jahr mit Treffern gewinnt; innerhalb davon zuerst die, die dem heutigen Datum am naechsten sind.
    static func throwback(_ songs: [ShelfSong], now: Date = Date(), windowDays: Int = 10, maxYears: Int = 15,
                          limit: Int = 12, calendar: Calendar = .current) -> Throwback? {
        for years in 1...max(1, maxYears) {
            guard let anchor = calendar.date(byAdding: .year, value: -years, to: now) else { continue }
            let window = Double(windowDays) * 86_400
            var hits: [(id: UUID, added: Date, distance: Double)] = []
            for song in songs {
                let distance = abs(song.dateAdded.timeIntervalSince(anchor))
                if distance <= window { hits.append((song.id, song.dateAdded, distance)) }
            }
            hits.sort { $0.distance != $1.distance ? $0.distance < $1.distance : $0.added < $1.added }
            if !hits.isEmpty { return Throwback(yearsAgo: years, ids: hits.prefix(limit).map { $0.id }) }
        }
        return nil
    }
}

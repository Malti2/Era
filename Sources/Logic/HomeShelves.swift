import Foundation

// Zusaetzliche Home-Regale als reine Logik: Vergessenes und Wiederentdeckenswertes.

struct ShelfSong: Equatable {
    var id: UUID
    var playCount: Int
    var lastPlayedAt: Date?
    var dateAdded: Date
    var isFavorite: Bool

    init(id: UUID = UUID(), playCount: Int = 0, lastPlayedAt: Date? = nil,
         dateAdded: Date = Date(timeIntervalSince1970: 0), isFavorite: Bool = false) {
        self.id = id
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.dateAdded = dateAdded
        self.isFavorite = isFavorite
    }
}

enum HomeShelves {
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
}

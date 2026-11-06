import Foundation

// Auswahl-Logik fuer die Home-Regale (rein, testbar).
enum HomeShelves {
    struct Candidate: Equatable {
        var id: UUID
        var playCount: Int
        var lastPlayedAt: Date?
        var dateAdded: Date
        var isFavorite: Bool
    }

    static let staleAfterDays = 30
    static let newGraceDays = 14

    /// Songs worth rediscovering: not heard for a month (or never played and no longer
    /// brand new). Favorites come first, then the ones left untouched the longest.
    static func rediscover(_ items: [Candidate], now: Date = Date(), calendar: Calendar = .current, limit: Int = 12) -> [UUID] {
        func eligible(_ item: Candidate) -> Bool {
            if let last = item.lastPlayedAt {
                guard let cutoff = calendar.date(byAdding: .day, value: -staleAfterDays, to: now) else { return false }
                return last < cutoff
            }
            guard let cutoff = calendar.date(byAdding: .day, value: -newGraceDays, to: now) else { return false }
            return item.dateAdded < cutoff
        }
        let sorted = items.filter(eligible).sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            let l = lhs.lastPlayedAt ?? lhs.dateAdded, r = rhs.lastPlayedAt ?? rhs.dateAdded
            if l != r { return l < r }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return Array(sorted.prefix(limit).map(\.id))
    }
}

import Foundation

// Bewertungs-Uebersicht und "Songs bewerten"-Warteschlange - reine Logik auf Snapshots.

struct RatingStats: Equatable {
    /// Index 0 = nicht bewertet, 1...5 = Sterne.
    private(set) var distribution: [Int]

    static func make(from ratings: [Int]) -> RatingStats {
        var counts = Array(repeating: 0, count: SongRating.range.upperBound + 1)
        for rating in ratings { counts[SongRating.clamp(rating)] += 1 }
        return RatingStats(distribution: counts)
    }

    var total: Int { distribution.reduce(0, +) }
    var unrated: Int { distribution[0] }
    var rated: Int { total - unrated }
    func count(for stars: Int) -> Int { distribution[SongRating.clamp(stars)] }

    /// Durchschnitt ueber bewertete Songs, 0 wenn keiner bewertet ist.
    var average: Double {
        guard rated > 0 else { return 0 }
        let sum = SongRating.range.reduce(0) { $0 + $1 * distribution[$1] }
        return Double(sum) / Double(rated)
    }

    var topRated: Int { SongRating.range.filter { $0 >= SongRating.topRatedMinimum }.reduce(0) { $0 + distribution[$1] } }

    /// Anteil der bewerteten Songs mit genau dieser Sternzahl (0...1).
    func share(of stars: Int) -> Double { rated > 0 ? Double(count(for: stars)) / Double(rated) : 0 }
}

struct RatingCandidate: Equatable {
    var id: UUID
    var rating: Int
    var playCount: Int
    var isFavorite: Bool
    var lastPlayedAt: Date?
    var dateAdded: Date
}

enum RatingReview {
    /// Unbewertete Songs, die sich am meisten lohnen: oft gehoert, Favoriten, zuletzt gehoert.
    /// Reihenfolge ist deterministisch (Gleichstand: neuer hinzugefuegt zuerst, dann Id).
    static func queue(from candidates: [RatingCandidate], limit: Int = 50) -> [UUID] {
        let open = candidates.filter { SongRating.clamp($0.rating) == 0 }
        let sorted = open.sorted { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb { return sa > sb }
            switch (a.lastPlayedAt, b.lastPlayedAt) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if a.dateAdded != b.dateAdded { return a.dateAdded > b.dateAdded }
            return a.id.uuidString < b.id.uuidString
        }
        return Array(sorted.prefix(max(0, limit)).map(\.id))
    }

    static func score(_ c: RatingCandidate) -> Int { max(0, c.playCount) * 2 + (c.isFavorite ? 3 : 0) }
}

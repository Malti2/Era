import Foundation

// "Aehnliche Songs" fuer Radio und Autoplay: reine Logik ohne SwiftData.
// Aehnlichkeit = gleicher Kuenstler/Album/Era, gemeinsame Tags und Status, nahes Jahr.
// Leichter, seed-stabiler Zufall sorgt dafuer, dass Radio nicht jedes Mal identisch klingt.

struct SimilarityProfile: Equatable {
    var id: UUID
    var artist: String
    var album: String
    var era: String
    var year: Int?
    var tags: [String]
    var statuses: [String]
    var isFavorite: Bool
    var rating: Int
    var lastPlayedAt: Date?

    init(id: UUID = UUID(), artist: String = "", album: String = "", era: String = "", year: Int? = nil,
         tags: [String] = [], statuses: [String] = [], isFavorite: Bool = false, rating: Int = 0,
         lastPlayedAt: Date? = nil) {
        self.id = id
        self.artist = artist
        self.album = album
        self.era = era
        self.year = year
        self.tags = tags
        self.statuses = statuses
        self.isFavorite = isFavorite
        self.rating = rating
        self.lastPlayedAt = lastPlayedAt
    }
}

enum SimilarSongs {
    /// Mindestpunktzahl, damit ein Song ueberhaupt als "aehnlich" gilt.
    static let minimumScore = 1.0

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ a: String, _ b: String) -> Bool {
        let x = fold(a), y = fold(b)
        return !x.isEmpty && x == y
    }

    /// Deterministische Aehnlichkeit zweier Songs (ohne Zufall und ohne Wiedergabe-Verlauf).
    static func similarity(_ seed: SimilarityProfile, _ other: SimilarityProfile) -> Double {
        var score = 0.0
        if matches(seed.artist, other.artist) { score += 3 }
        if matches(seed.album, other.album) { score += 2 }
        if matches(seed.era, other.era) { score += 2.5 }
        let ownTags = Set(other.tags.map(fold))
        let sharedTags = Set(seed.tags.map(fold)).intersection(ownTags).count
        score += min(Double(sharedTags), 4) * 1.5
        let ownStatuses = Set(other.statuses.map(fold))
        score += Set(seed.statuses.map(fold)).intersection(ownStatuses).isEmpty ? 0 : 0.75
        if let a = seed.year, let b = other.year {
            let gap = abs(a - b)
            if gap <= 1 { score += 1 } else if gap <= 3 { score += 0.5 }
        }
        return score
    }

    /// Die `limit` aehnlichsten Songs fuer `seed`, ohne `excluding`. Bei gleichem Seed gleiche Reihenfolge.
    static func rank(seed: SimilarityProfile, in library: [SimilarityProfile], excluding: Set<UUID> = [],
                     limit: Int = 25, now: Date = Date(), randomSeed: UInt64 = 0) -> [UUID] {
        var generator = SeededGenerator(seed: randomSeed)
        let scored = library.compactMap { song -> (song: SimilarityProfile, score: Double)? in
            guard song.id != seed.id, !excluding.contains(song.id) else { return nil }
            var score = similarity(seed, song)
            guard score >= minimumScore else { return nil }
            if song.isFavorite { score += 0.5 }
            if SongRating.clamp(song.rating) >= SongRating.topRatedMinimum { score += 0.5 }
            // Was gerade erst lief, kommt nicht sofort wieder.
            if let last = song.lastPlayedAt, now.timeIntervalSince(last) < 86_400 { score -= 1.5 }
            score += Double.random(in: 0..<0.9, using: &generator)
            return (song, score)
        }
        let top = scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.song.id.uuidString < $1.song.id.uuidString }
            .prefix(max(0, limit))
            .map(\.song)
        return spreadArtists(Array(top)).map(\.id)
    }

    /// Verhindert, dass derselbe Kuenstler mehr als zweimal direkt hintereinander kommt (sonst stabile Reihenfolge).
    static func spreadArtists(_ songs: [SimilarityProfile]) -> [SimilarityProfile] {
        var rest = songs
        var out: [SimilarityProfile] = []
        while !rest.isEmpty {
            let a = out.count >= 1 ? fold(out[out.count - 1].artist) : ""
            let b = out.count >= 2 ? fold(out[out.count - 2].artist) : ""
            let blocked = !a.isEmpty && a == b
            let index = rest.firstIndex { !blocked || fold($0.artist) != a } ?? 0
            out.append(rest.remove(at: index))
        }
        return out
    }
}

import Foundation

// Mixes fuer die Startseite: Tages-Mix, Deep Cuts und Frisch importiert.
// Reine Logik. Gewichtete Zufallsauswahl mit festem Seed (Kalendertag), damit ein Mix
// den ganzen Tag gleich bleibt, und Kuenstler-Abstand, damit nicht dreimal derselbe hintereinander kommt.

struct MixCandidate: Equatable {
    var id: UUID
    var artist: String
    var playCount: Int
    var lastPlayedAt: Date?
    var dateAdded: Date
    var isFavorite: Bool

    init(id: UUID = UUID(), artist: String = "", playCount: Int = 0, lastPlayedAt: Date? = nil,
         dateAdded: Date = Date(timeIntervalSince1970: 0), isFavorite: Bool = false) {
        self.id = id
        self.artist = artist
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.dateAdded = dateAdded
        self.isFavorite = isFavorite
    }
}

enum MixKind: String, CaseIterable, Identifiable {
    case daily, deepCuts, fresh
    var id: String { rawValue }
}

/// Kleiner deterministischer Zufallsgenerator (SplitMix64) - gleicher Seed, gleiche Reihenfolge.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum MixBuilder {
    /// Mindestgroesse, ab der ein Mix auf der Startseite erscheint.
    static let minimumSize = 6

    static func daySeed(for date: Date = Date(), calendar: Calendar = .current) -> UInt64 {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0, month = parts.month ?? 0, day = parts.day ?? 0
        let value: Int = year * 10_000 + month * 100 + day
        return UInt64(max(0, value))
    }

    static func make(_ kind: MixKind, from songs: [MixCandidate], now: Date = Date(), seed: UInt64? = nil,
                     size: Int = 25, calendar: Calendar = .current) -> [UUID] {
        let eligible = songs.filter { isEligible($0, kind: kind, now: now) }
        guard !eligible.isEmpty else { return [] }
        var generator = SeededGenerator(seed: (seed ?? daySeed(for: now, calendar: calendar)) &+ UInt64(kind.hashSeed))
        // Efraimidis-Spirakis: Schluessel u^(1/w), groesste zuerst = gewichtete Ziehung ohne Zuruecklegen.
        let keyed = eligible.map { song -> (song: MixCandidate, key: Double) in
            let weight = max(0.001, self.weight(song, kind: kind, now: now))
            let u = Double.random(in: 0.000_001..<1, using: &generator)
            return (song, pow(u, 1 / weight))
        }
        let picked = keyed.sorted { $0.key != $1.key ? $0.key > $1.key : $0.song.id.uuidString < $1.song.id.uuidString }
            .prefix(size).map(\.song)
        return spreadArtists(Array(picked)).map(\.id)
    }

    static func isEligible(_ song: MixCandidate, kind: MixKind, now: Date) -> Bool {
        let day = 86_400.0
        let age = now.timeIntervalSince(song.dateAdded)
        switch kind {
        case .daily:
            return true
        case .deepCuts:
            return song.playCount <= 2 && age >= 14 * day
        case .fresh:
            return age <= 30 * day
        }
    }

    /// Relative Ziehungswahrscheinlichkeit eines Songs.
    static func weight(_ song: MixCandidate, kind: MixKind, now: Date) -> Double {
        let day = 86_400.0
        switch kind {
        case .daily:
            var w = 1.0
            if song.isFavorite { w *= 2.5 }
            if let last = song.lastPlayedAt {
                let idle = now.timeIntervalSince(last) / day
                if idle < 2 { w *= 0.25 } else if idle >= 30 { w *= 2 }
            } else if now.timeIntervalSince(song.dateAdded) > 3 * day {
                w *= 1.5 // nie gespielt, aber schon laenger da
            }
            w *= 1 + min(Double(song.playCount), 20) / 20
            return w
        case .deepCuts:
            return 1 / Double(1 + song.playCount) + (song.isFavorite ? 0.4 : 0)
        case .fresh:
            let ageDays = max(0, now.timeIntervalSince(song.dateAdded) / day)
            var w = 1.5 - min(ageDays, 30) / 30 // neuere zuerst
            if song.playCount == 0 { w += 1 }
            return w
        }
    }

    /// Ordnet so um, dass derselbe Kuenstler moeglichst nicht direkt hintereinander steht (Reihenfolge sonst stabil).
    static func spreadArtists(_ songs: [MixCandidate]) -> [MixCandidate] {
        var rest = songs
        var out: [MixCandidate] = []
        while !rest.isEmpty {
            let lastArtist = out.last.map { normalized($0.artist) }
            let index = rest.firstIndex { lastArtist == nil || lastArtist!.isEmpty || normalized($0.artist) != lastArtist } ?? 0
            out.append(rest.remove(at: index))
        }
        return out
    }

    private static func normalized(_ artist: String) -> String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension MixKind {
    var hashSeed: Int {
        switch self {
        case .daily: 11
        case .deepCuts: 23
        case .fresh: 37
        }
    }
}

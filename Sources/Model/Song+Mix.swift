import Foundation

extension Song {
    var mixCandidate: MixCandidate {
        MixCandidate(id: id, artist: artist, playCount: playCount, lastPlayedAt: lastPlayedAt,
                     dateAdded: dateAdded, isFavorite: isFavorite)
    }
}

enum MixPlaylist {
    /// Spielbare Songs eines Mixes in Abspielreihenfolge (gemeinsam fuer Startseite und Siri).
    static func songs(_ kind: MixKind, in library: [Song], now: Date = Date()) -> [Song] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = MixBuilder.make(kind, from: library.map(\.mixCandidate), now: now)
        return ids.compactMap { byID[$0] }.filter { $0.primaryVersion != nil }
    }
}

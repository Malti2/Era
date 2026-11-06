import Foundation

// Kennzahlen zu einer Sammlung (Kuenstler, Album, Era) fuer den Kopf der Detailseite.

struct ProfileSong: Equatable {
    var title: String
    var playCount: Int
    var isFavorite: Bool
    var versionCount: Int
}

struct CollectionProfile: Equatable {
    var songs = 0
    var versions = 0
    var plays = 0
    var favorites = 0
    var neverPlayed = 0
    var mostPlayed: (title: String, plays: Int)?

    static func == (lhs: CollectionProfile, rhs: CollectionProfile) -> Bool {
        lhs.songs == rhs.songs && lhs.versions == rhs.versions && lhs.plays == rhs.plays
            && lhs.favorites == rhs.favorites && lhs.neverPlayed == rhs.neverPlayed
            && lhs.mostPlayed?.title == rhs.mostPlayed?.title && lhs.mostPlayed?.plays == rhs.mostPlayed?.plays
    }

    static func make(from list: [ProfileSong]) -> CollectionProfile {
        var profile = CollectionProfile()
        var best: ProfileSong?
        for song in list {
            profile.songs += 1
            profile.versions += song.versionCount
            profile.plays += song.playCount
            if song.isFavorite { profile.favorites += 1 }
            if song.playCount == 0 { profile.neverPlayed += 1 }
            if song.playCount > 0 {
                if let current = best {
                    if song.playCount > current.playCount
                        || (song.playCount == current.playCount && song.title.localizedStandardCompare(current.title) == .orderedAscending) {
                        best = song
                    }
                } else {
                    best = song
                }
            }
        }
        profile.mostPlayed = best.map { ($0.title, $0.playCount) }
        return profile
    }
}

import Foundation

extension Song {
    /// Wertkopie fuer `SimilarSongs` (Radio/Autoplay).
    var similarityProfile: SimilarityProfile {
        SimilarityProfile(id: id, artist: artist, album: album, era: era, year: year,
                          tags: personalTags.map(\.name), statuses: statusTags.map(\.name),
                          isFavorite: isFavorite, rating: rating, lastPlayedAt: lastPlayedAt)
    }
}

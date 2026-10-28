import Foundation

extension Song {
    /// Wertkopie fuer die SwiftData-freie Suchlogik (`SongSearch`).
    var searchable: SearchableSong {
        SearchableSong(
            id: id, title: title, artist: artist, album: album, era: era, year: year,
            tags: personalTags.map(\.name), statuses: statusTags.map(\.name),
            versionNames: versions.map(\.name), isFavorite: isFavorite, playCount: playCount
        )
    }
}

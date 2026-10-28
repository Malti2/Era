import SwiftUI

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

extension Song {
    var sortRow: SortRow {
        SortRow(id: id, title: title, artist: artist, year: year, playCount: playCount, dateAdded: dateAdded, duration: duration)
    }
}

extension LibrarySort {
    var label: LocalizedStringKey {
        switch self {
        case .recent: "Recently Added"
        case .title: "Title"
        case .artist: "Artist"
        case .year: "Year"
        case .mostPlayed: "Most Played"
        case .longest: "Longest"
        }
    }
}

import SwiftUI

extension Song {
    /// Wertkopie fuer die SwiftData-freie Suchlogik (`SongSearch`).
    var searchable: SearchableSong {
        SearchableSong(
            id: id, title: title, artist: artist, album: album, era: era, year: year,
            tags: personalTags.map(\.name), statuses: statusTags.map(\.name),
            versionNames: versions.map(\.name), isFavorite: isFavorite, playCount: playCount,
            notes: notes, markerLabels: versions.flatMap { $0.markers.map(\.label).filter { !$0.isEmpty } },
            markerCount: versions.reduce(0) { $0 + $1.markers.count },
            dateAdded: dateAdded, lastPlayedAt: lastPlayedAt, duration: duration, rating: rating
        )
    }
}

extension Song {
    var eraSong: EraSong {
        EraSong(id: id, era: era, year: year, duration: duration, statuses: statusTags.map(\.name))
    }
}

extension Song {
    var sortRow: SortRow {
        SortRow(id: id, title: title, artist: artist, year: year, playCount: playCount, dateAdded: dateAdded, duration: duration, rating: rating)
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
        case .rating: "Rating"
        }
    }
}

extension LibraryFilter.Attribute {
    var title: LocalizedStringKey {
        switch self {
        case .notPlayed: "Not Played Yet"
        case .hasNotes: "With Notes"
        case .multipleVersions: "Multiple Versions"
        case .topRated: "Top Rated"
        }
    }
}

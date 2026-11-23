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
            dateAdded: dateAdded, lastPlayedAt: lastPlayedAt, duration: duration, rating: rating, trackNumber: trackNumber,
            hasArtwork: versions.contains { $0.artworkFile != nil }
        )
    }
}

extension Song {
    /// Schlanke Variante fuer `LibraryFilter`: spart das Dekodieren der Marker-JSONs jeder Version,
    /// die der Filter nie liest (relevant bei grossen Bibliotheken, der Filter laeuft bei jedem Neuzeichnen).
    var filterable: SearchableSong {
        SearchableSong(
            id: id, title: title, tags: personalTags.map(\.name), statuses: statusTags.map(\.name),
            versionNames: versions.map(\.name), isFavorite: isFavorite, playCount: playCount,
            notes: notes, rating: rating
        )
    }
}

extension Song {
    /// Wie `searchable`, nur mit gesetztem Dubletten-Flag (fuer `duplicates:` in gespeicherten Suchen).
    func searchableCopy(isDuplicate: Bool) -> SearchableSong {
        var copy = searchable
        copy.isDuplicate = isDuplicate
        return copy
    }
}

extension Array where Element == Song {
    /// IDs der Songs, die Teil einer Dubletten-Gruppe sind (gleicher Titel + Kuenstler, wie im Library Check).
    var duplicateIDs: Set<UUID> {
        LibraryHealth.duplicateIDs(in: map { HealthSong(id: $0.id, title: $0.title, artist: $0.artist, versions: []) })
    }

    /// SearchableSong-Snapshots mit gesetztem Dubletten-Flag - ein Durchlauf statt pro Song neu.
    var searchables: [SearchableSong] {
        let dups = duplicateIDs
        return map { $0.searchableCopy(isDuplicate: dups.contains($0.id)) }
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
        case .unrated: "Not Rated"
        }
    }
}

import Foundation

// Filter fuer die Songliste der Bibliothek (Favoriten, Status, Tags) als reine Logik.
// Status wirkt als ODER (Demo oder Leak), Tags als UND (jeder gewaehlte Tag muss passen).

struct LibraryFilter: Equatable {
    var favoritesOnly = false
    var statuses: Set<String> = []
    var tags: Set<String> = []

    var isActive: Bool { favoritesOnly || !statuses.isEmpty || !tags.isEmpty }
    var activeCount: Int { (favoritesOnly ? 1 : 0) + statuses.count + tags.count }

    func matches(_ song: SearchableSong) -> Bool {
        if favoritesOnly && !song.isFavorite { return false }
        if !statuses.isEmpty {
            let own = Set(song.statuses.map(SongSearch.fold))
            if own.isDisjoint(with: statuses.map(SongSearch.fold)) { return false }
        }
        if !tags.isEmpty {
            let own = Set(song.tags.map(SongSearch.fold))
            if !Set(tags.map(SongSearch.fold)).isSubset(of: own) { return false }
        }
        return true
    }

    /// Ids der passenden Songs in Eingabereihenfolge.
    func ids(in songs: [SearchableSong]) -> [UUID] {
        isActive ? songs.filter(matches).map(\.id) : songs.map(\.id)
    }

    mutating func toggle(status: String) {
        if statuses.contains(status) { statuses.remove(status) } else { statuses.insert(status) }
    }

    mutating func toggle(tag: String) {
        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
    }
}

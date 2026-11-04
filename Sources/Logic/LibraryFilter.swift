import Foundation

// Filter fuer die Songliste der Bibliothek (Favoriten, Status, Tags, Eigenschaften) als reine Logik.
// Status wirkt als ODER (Demo oder Leak), Tags und Eigenschaften als UND (alles muss passen).

struct LibraryFilter: Equatable, Codable {
    var favoritesOnly = false
    var statuses: Set<String> = []
    var tags: Set<String> = []
    var attributes: Set<Attribute> = []

    /// Eigenschaften, die sich aus dem Song selbst ergeben - hilft beim Aufraeumen ("Was habe ich noch nie gehoert?").
    enum Attribute: String, Codable, CaseIterable, Hashable {
        case notPlayed, hasNotes, multipleVersions

        func matches(_ song: SearchableSong) -> Bool {
            switch self {
            case .notPlayed: song.playCount == 0
            case .hasNotes: !song.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .multipleVersions: song.versionNames.count > 1
            }
        }
    }

    init(favoritesOnly: Bool = false, statuses: Set<String> = [], tags: Set<String> = [], attributes: Set<Attribute> = []) {
        self.favoritesOnly = favoritesOnly
        self.statuses = statuses
        self.tags = tags
        self.attributes = attributes
    }

    // Aeltere gespeicherte Filter kennen `attributes` noch nicht.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoritesOnly = try container.decodeIfPresent(Bool.self, forKey: .favoritesOnly) ?? false
        statuses = try container.decodeIfPresent(Set<String>.self, forKey: .statuses) ?? []
        tags = try container.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
        attributes = (try? container.decodeIfPresent(Set<Attribute>.self, forKey: .attributes)) ?? []
    }

    var isActive: Bool { favoritesOnly || !statuses.isEmpty || !tags.isEmpty || !attributes.isEmpty }
    var activeCount: Int { (favoritesOnly ? 1 : 0) + statuses.count + tags.count + attributes.count }

    func matches(_ song: SearchableSong) -> Bool {
        if favoritesOnly && !song.isFavorite { return false }
        if !attributes.allSatisfy({ $0.matches(song) }) { return false }
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

    /// Fuer `@AppStorage`: der Filter bleibt ueber App-Starts erhalten. Kaputter Text = kein Filter.
    var encoded: String {
        guard isActive, let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(_ raw: String) -> LibraryFilter {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let filter = try? JSONDecoder().decode(LibraryFilter.self, from: data) else { return LibraryFilter() }
        return filter
    }

    mutating func toggle(status: String) {
        if statuses.contains(status) { statuses.remove(status) } else { statuses.insert(status) }
    }

    mutating func toggle(_ attribute: Attribute) {
        if attributes.contains(attribute) { attributes.remove(attribute) } else { attributes.insert(attribute) }
    }

    mutating func toggle(tag: String) {
        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
    }
}

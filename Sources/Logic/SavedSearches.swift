import Foundation

// Angepinnte Suchen (Operator-Abfragen wie "tag:demo -has:notes") fuer den Start der Suche.
struct SavedSearch: Codable, Equatable, Identifiable {
    var id: UUID
    var query: String

    init(id: UUID = UUID(), query: String) {
        self.id = id
        self.query = query
    }
}

enum SavedSearches {
    static let limit = 12

    private static func key(_ query: String) -> String {
        SongSearch.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func contains(_ query: String, in list: [SavedSearch]) -> Bool {
        let k = key(query)
        return !k.isEmpty && list.contains { key($0.query) == k }
    }

    /// Pinnt die Suche (vorne) oder loest sie wieder, wenn sie schon gepinnt ist.
    static func toggling(_ query: String, in list: [SavedSearch]) -> [SavedSearch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = key(trimmed)
        guard !k.isEmpty else { return list }
        if contains(trimmed, in: list) { return list.filter { key($0.query) != k } }
        return Array(([SavedSearch(query: trimmed)] + list).prefix(limit))
    }

    static func encode(_ list: [SavedSearch]) -> Data? { try? JSONEncoder().encode(list) }

    static func decode(_ data: Data?) -> [SavedSearch] {
        guard let data, let list = try? JSONDecoder().decode([SavedSearch].self, from: data) else { return [] }
        return list
    }
}

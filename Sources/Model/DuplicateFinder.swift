import Foundation

// Findet Songs, die vermutlich dieselbe Aufnahme sind (gleicher Titel + Kuenstler
// nach Normalisierung), damit sie als Versionen zusammengefuehrt werden koennen.
enum DuplicateFinder {
    struct Item: Equatable {
        var id: UUID
        var title: String
        var artist: String
    }

    /// "Song (Remastered 2011) - Live" and "SONG" collapse to the same key;
    /// qualifiers like these are exactly what Era models as versions.
    static func normalized(_ text: String) -> String {
        var value = text
        // Drop bracketed qualifiers: (…) […]
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let start = value.range(of: open), let end = value.range(of: close, range: start.upperBound..<value.endIndex) {
                value.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        // Drop a trailing " - qualifier"
        if let dash = value.range(of: " - ") { value = String(value[..<dash.lowerBound]) }
        value = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let allowed = CharacterSet.alphanumerics
        value = String(value.unicodeScalars.filter { allowed.contains($0) })
        return value
    }

    static func key(title: String, artist: String) -> String {
        var a = artist.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if a.hasPrefix("the ") { a.removeFirst(4) }
        return normalized(title) + "\u{1F}" + normalized(a)
    }

    /// Groups of two or more song ids sharing a key. Songs without a usable title are ignored.
    static func groups(_ items: [Item]) -> [[UUID]] {
        var buckets: [String: [UUID]] = [:]
        var order: [String] = []
        for item in items {
            let title = normalized(item.title)
            guard !title.isEmpty else { continue }
            let k = key(title: item.title, artist: item.artist)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(item.id)
        }
        return order.compactMap { buckets[$0] }.filter { $0.count > 1 }.sorted { $0.count > $1.count }
    }
}

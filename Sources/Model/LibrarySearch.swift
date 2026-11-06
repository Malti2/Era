import Foundation

// Suche ueber die Bibliothek: mehrere Woerter (UND), akzent-/gross-kleinschreibungs-
// unabhaengig, Treffer im Titel zuerst. Rein und damit testbar.
enum LibrarySearch {
    struct Document: Equatable {
        var id: UUID
        var title: String
        var artist: String
        var album: String
        var era: String
        var tags: [String]
        var versions: [String]
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func tokens(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Ids of matching documents, best match first. Ties keep the input order.
    static func search(_ documents: [Document], query: String) -> [UUID] {
        let terms = tokens(query)
        guard !terms.isEmpty else { return [] }
        var scored: [(index: Int, id: UUID, score: Int)] = []
        for (index, doc) in documents.enumerated() {
            let title = fold(doc.title), artist = fold(doc.artist), album = fold(doc.album), era = fold(doc.era)
            let tags = doc.tags.map(fold), versions = doc.versions.map(fold)
            var total = 0
            var matchedAll = true
            for term in terms {
                var best = 0
                if title.hasPrefix(term) { best = 100 }
                else if title.split(separator: " ").contains(where: { $0.hasPrefix(term) }) { best = 80 }
                else if title.contains(term) { best = 60 }
                if artist.contains(term) { best = max(best, 50) }
                if album.contains(term) { best = max(best, 30) }
                if tags.contains(where: { $0.contains(term) }) { best = max(best, 25) }
                if versions.contains(where: { $0.contains(term) }) { best = max(best, 20) }
                if era.contains(term) { best = max(best, 15) }
                if best == 0 { matchedAll = false; break }
                total += best
            }
            if matchedAll { scored.append((index, doc.id, total)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.map(\.id)
    }
}

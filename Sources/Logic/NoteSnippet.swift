import Foundation

// Kurzer Ausschnitt aus Notizen/Marker-Namen rund um den Suchbegriff, damit die Trefferliste
// zeigt, WARUM ein Song gefunden wurde ("…das Gitarrenriff im Intro…").
enum NoteSnippet {
    /// Erster Kandidat, der einen Begriff enthaelt (Gross-/Kleinschreibung und Akzente egal).
    /// `radius` = Zeichen links und rechts vom Treffer; gekuerzte Enden bekommen "…".
    static func excerpt(in candidates: [String], terms: [String], radius: Int = 34) -> String? {
        guard !terms.isEmpty else { return nil }
        for candidate in candidates {
            let text = candidate.replacingOccurrences(of: "\n", with: " ")
            for term in terms where !term.isEmpty {
                guard let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                let lower = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
                let upper = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
                var piece = String(text[lower..<upper]).trimmingCharacters(in: .whitespaces)
                if lower > text.startIndex { piece = "…" + piece }
                if upper < text.endIndex { piece += "…" }
                return piece
            }
        }
        return nil
    }
}

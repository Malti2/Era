import Foundation

// Persoenliche Bewertung eines Songs: 0 = nicht bewertet, 1...5 Sterne.
enum SongRating {
    static let range = 1...5
    static let topRatedMinimum = 4

    static func clamp(_ value: Int) -> Int { min(range.upperBound, max(0, value)) }

    /// Tippen auf den aktuell gesetzten Stern loescht die Bewertung, sonst wird der Stern gesetzt.
    static func toggled(current: Int, tapped: Int) -> Int {
        let tapped = clamp(tapped)
        return tapped == clamp(current) ? 0 : tapped
    }

    /// VoiceOver-Schritte: Wert +/- 1, ohne ueber 0...5 hinauszulaufen.
    static func adjusted(_ current: Int, by step: Int) -> Int { clamp(clamp(current) + step) }

    static func stars(_ rating: Int) -> String {
        let value = clamp(rating)
        return String(repeating: "★", count: value) + String(repeating: "☆", count: range.upperBound - value)
    }
}

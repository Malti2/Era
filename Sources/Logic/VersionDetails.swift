import Foundation

// Eingaben des Version-Editors: Jahr parsen und Abweichungen vom Song bereinigen.
enum VersionDetails {
    enum YearInput: Equatable {
        case empty
        case valid(Int)
        case invalid
    }

    static let yearRange = 1900...2200

    static func parseYear(_ text: String) -> YearInput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        guard let year = Int(trimmed), yearRange.contains(year) else { return .invalid }
        return .valid(year)
    }

    /// nil = "same as the song": blank input, or text identical to the song's own value.
    static func override(_ input: String, songValue: String) -> String? {
        guard let cleaned = BulkTagging.cleanName(input) else { return nil }
        return cleaned == BulkTagging.cleanName(songValue) ? nil : cleaned
    }
}

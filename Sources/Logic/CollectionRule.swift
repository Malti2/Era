import Foundation

// Regel einer Sammlung (Pack): Songs muessen ALLE gewaehlten Tags und ALLE gewaehlten
// Status haben. Reine Logik, damit Editor, Liste und Detailansicht dasselbe meinen.
struct CollectionRule: Equatable {
    var tagIDs: Set<UUID> = []
    var statusNames: Set<String> = []

    /// Eine Regel ohne Bedingung wuerde die ganze Bibliothek enthalten - so etwas legt der Editor nicht an.
    var isEmpty: Bool { tagIDs.isEmpty && statusNames.isEmpty }

    func matches(tagIDs songTagIDs: Set<UUID>, statuses songStatuses: Set<String>) -> Bool {
        tagIDs.isSubset(of: songTagIDs) && statusNames.isSubset(of: songStatuses)
    }

    mutating func toggle(tag id: UUID) {
        if tagIDs.contains(id) { tagIDs.remove(id) } else { tagIDs.insert(id) }
    }

    mutating func toggle(status name: String) {
        if statusNames.contains(name) { statusNames.remove(name) } else { statusNames.insert(name) }
    }
}

enum CollectionName {
    enum Check: Equatable {
        case ok(String)
        case empty
        case duplicate
    }

    /// Prueft einen Namen gegen die vorhandenen (ohne Gross-/Kleinschreibung). `editing` ist der aktuelle
    /// Name der bearbeiteten Sammlung und zaehlt nicht als Duplikat.
    static func validate(_ proposed: String, existing: [String], editing current: String? = nil) -> Check {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .empty }
        let taken = existing.contains { other in
            other.localizedCaseInsensitiveCompare(name) == .orderedSame
                && other.localizedCaseInsensitiveCompare(current ?? "\u{0}") != .orderedSame
        }
        return taken ? .duplicate : .ok(name)
    }
}

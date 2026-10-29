import Foundation

// Mehrfachauswahl in der Bibliothek und Tag-Logik fuer Sammelaktionen - ohne SwiftData testbar.

struct BulkSelection: Equatable {
    private(set) var ids: Set<UUID> = []

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    mutating func toggle(_ id: UUID) {
        if !ids.insert(id).inserted { ids.remove(id) }
    }

    mutating func selectAll(_ all: [UUID]) { ids.formUnion(all) }
    mutating func clear() { ids = [] }

    /// Drops ids that no longer exist (deleted songs), so counts never include ghosts.
    mutating func prune(to valid: Set<UUID>) { ids.formIntersection(valid) }

    func coversAll(of all: [UUID]) -> Bool {
        !all.isEmpty && all.allSatisfy(ids.contains)
    }
}

enum TagCoverage: Equatable {
    case none, some, all
}

enum BulkTagging {
    /// Whether none, some or all of the songs carry the tag (names compare case-insensitively).
    static func coverage(of tag: String, in songTags: [[String]]) -> TagCoverage {
        guard !songTags.isEmpty else { return .none }
        let key = tag.lowercased()
        let carrying = songTags.filter { $0.contains { $0.lowercased() == key } }.count
        if carrying == 0 { return .none }
        return carrying == songTags.count ? .all : .some
    }

    /// Tapping a tag: everything that is not fully tagged becomes fully tagged, otherwise the tag is removed.
    static func shouldAdd(_ coverage: TagCoverage) -> Bool { coverage != .all }

    /// Trimmed, single-spaced tag name; nil when nothing usable is left.
    static func cleanName(_ raw: String) -> String? {
        let parts = raw.split(whereSeparator: { $0.isWhitespace })
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

enum TagRename: Equatable {
    case invalid
    case unchanged
    /// The new name belongs to another tag - both are combined into it.
    case merge(into: String)
    case rename(to: String)

    static func resolve(_ proposed: String, current: String, existing: [String]) -> TagRename {
        guard let name = BulkTagging.cleanName(proposed) else { return .invalid }
        if name == current { return .unchanged }
        let key = name.lowercased()
        if let other = existing.first(where: { $0.lowercased() == key && $0 != current }) {
            return .merge(into: other)
        }
        return .rename(to: name)
    }
}

import Foundation

// Regel einer Sammlung (Pack): Songs muessen ALLE (oder, im Modus "eine", mindestens EINE) der
// gewaehlten Tags/Status haben und duerfen keinen der ausgeschlossenen haben. Reine Logik,
// damit Editor, Liste und Detailansicht dasselbe meinen.
struct CollectionRule: Equatable {
    /// Zustand einer Bedingung im Editor: aus -> dabei -> ohne -> aus.
    enum Mark: Equatable { case none, include, exclude }

    var tagIDs: Set<UUID> = []
    var statusNames: Set<String> = []
    /// Songs mit einem dieser Tags/Status gehoeren nie zur Sammlung.
    var excludedTagIDs: Set<UUID> = []
    var excludedStatusNames: Set<String> = []
    /// false: alle gewaehlten Bedingungen muessen passen; true: eine reicht.
    var matchAny = false

    init(tagIDs: Set<UUID> = [], statusNames: Set<String> = [],
         excludedTagIDs: Set<UUID> = [], excludedStatusNames: Set<String> = [], matchAny: Bool = false) {
        self.tagIDs = tagIDs
        self.statusNames = statusNames
        self.excludedTagIDs = excludedTagIDs
        self.excludedStatusNames = excludedStatusNames
        self.matchAny = matchAny
    }

    /// Eine Regel ohne Bedingung wuerde die ganze Bibliothek enthalten - so etwas legt der Editor nicht an.
    var isEmpty: Bool { includeCount == 0 && excludedTagIDs.isEmpty && excludedStatusNames.isEmpty }
    var includeCount: Int { tagIDs.count + statusNames.count }
    /// "Alle/Eine"-Auswahl ergibt erst ab zwei positiven Bedingungen einen Unterschied.
    var needsMatchMode: Bool { includeCount >= 2 }

    func matches(tagIDs songTagIDs: Set<UUID>, statuses songStatuses: Set<String>) -> Bool {
        guard excludedTagIDs.isDisjoint(with: songTagIDs), excludedStatusNames.isDisjoint(with: songStatuses) else { return false }
        if includeCount == 0 { return true } // reine "Ohne"-Regel: alles ausser den Ausnahmen
        if matchAny {
            return !tagIDs.isDisjoint(with: songTagIDs) || !statusNames.isDisjoint(with: songStatuses)
        }
        return tagIDs.isSubset(of: songTagIDs) && statusNames.isSubset(of: songStatuses)
    }

    mutating func toggle(tag id: UUID) {
        excludedTagIDs.remove(id)
        if tagIDs.contains(id) { tagIDs.remove(id) } else { tagIDs.insert(id) }
    }

    mutating func toggle(status name: String) {
        excludedStatusNames.remove(name)
        if statusNames.contains(name) { statusNames.remove(name) } else { statusNames.insert(name) }
    }

    func mark(tag id: UUID) -> Mark {
        tagIDs.contains(id) ? .include : (excludedTagIDs.contains(id) ? .exclude : .none)
    }

    func mark(status name: String) -> Mark {
        statusNames.contains(name) ? .include : (excludedStatusNames.contains(name) ? .exclude : .none)
    }

    mutating func cycle(tag id: UUID) {
        switch mark(tag: id) {
        case .none: tagIDs.insert(id)
        case .include: tagIDs.remove(id); excludedTagIDs.insert(id)
        case .exclude: excludedTagIDs.remove(id)
        }
    }

    mutating func cycle(status name: String) {
        switch mark(status: name) {
        case .none: statusNames.insert(name)
        case .include: statusNames.remove(name); excludedStatusNames.insert(name)
        case .exclude: excludedStatusNames.remove(name)
        }
    }

    /// Entfernt Tags, die es nicht mehr gibt (geloescht/zusammengefuehrt), aus allen Bedingungen.
    func pruned(toExistingTagIDs existing: Set<UUID>) -> CollectionRule {
        var copy = self
        copy.tagIDs.formIntersection(existing)
        copy.excludedTagIDs.formIntersection(existing)
        return copy
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

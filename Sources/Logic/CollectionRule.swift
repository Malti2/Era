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
    /// Gespeicherte Suche (Syntax wie in der Suche, z. B. `era:synth plays:0 -tag:demo`); zusaetzlich zu den Tags/Status.
    var query = ""

    init(tagIDs: Set<UUID> = [], statusNames: Set<String> = [],
         excludedTagIDs: Set<UUID> = [], excludedStatusNames: Set<String> = [], matchAny: Bool = false, query: String = "") {
        self.tagIDs = tagIDs
        self.statusNames = statusNames
        self.excludedTagIDs = excludedTagIDs
        self.excludedStatusNames = excludedStatusNames
        self.matchAny = matchAny
        self.query = query
    }

    /// Eine Regel ohne Bedingung wuerde die ganze Bibliothek enthalten - so etwas legt der Editor nicht an.
    var isEmpty: Bool { includeCount == 0 && excludedTagIDs.isEmpty && excludedStatusNames.isEmpty && parsedQuery == nil }
    /// Die Suche, falls eine gesetzt ist und etwas bedeutet (nur Leerraum = keine Suche).
    var parsedQuery: SongSearchQuery? {
        let parsed = SongSearchQuery(query)
        return parsed.isEmpty ? nil : parsed
    }
    var includeCount: Int { tagIDs.count + statusNames.count }
    /// "Alle/Eine"-Auswahl ergibt erst ab zwei positiven Bedingungen einen Unterschied.
    var needsMatchMode: Bool { includeCount >= 2 }

    /// Tags/Status UND gespeicherte Suche. `searchable` wird nur gebaut, wenn eine Suche gesetzt ist.
    func matches(tagIDs songTagIDs: Set<UUID>, statuses songStatuses: Set<String>, searchable: () -> SearchableSong) -> Bool {
        guard matches(tagIDs: songTagIDs, statuses: songStatuses) else { return false }
        guard let parsed = parsedQuery else { return true }
        return SongSearch.match(searchable(), query: parsed) != nil
    }

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

    /// Namen der Bedingungen fuer die Kurzbeschreibung in Listen: Status zuerst, dann Tags, jeweils sortiert.
    /// Tags ohne Namen (geloescht) fallen weg.
    func labels(tagName: (UUID) -> String?) -> (include: [String], exclude: [String]) {
        func sorted(_ status: Set<String>, _ ids: Set<UUID>) -> [String] {
            status.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                + ids.compactMap(tagName).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        return (sorted(statusNames, tagIDs), sorted(excludedStatusNames, excludedTagIDs))
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

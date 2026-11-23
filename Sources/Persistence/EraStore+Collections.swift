import Foundation
import SwiftData

// Sammlungen (Packs) anlegen, bearbeiten, loeschen. Namen sind eindeutig, eine Sammlung braucht mindestens eine Bedingung.
extension Pack {
    var rule: CollectionRule {
        get {
            var rule = CollectionRule(tagIDs: Set(tagIDs), statusNames: Set(statusNames),
                           excludedTagIDs: Set(excludedTagIDs), excludedStatusNames: Set(excludedStatusNames), matchAny: matchAny, query: searchQuery)
            rule.groups = CollectionRule.decodeGroups(groupsJSON)
            return rule
        }
        set {
            let clean = newValue.normalized()
            tagIDs = Array(clean.tagIDs)
            statusNames = Array(clean.statusNames).sorted()
            excludedTagIDs = Array(clean.excludedTagIDs)
            excludedStatusNames = Array(clean.excludedStatusNames).sorted()
            matchAny = clean.matchAny
            searchQuery = clean.query.trimmingCharacters(in: .whitespacesAndNewlines)
            groupsJSON = CollectionRule.encodeGroups(clean.groups)
        }
    }
}

extension Song {
    func matches(_ rule: CollectionRule) -> Bool {
        matches(rule, duplicateIDs: [])
    }

    /// Wie `matches(_:)`, nur dass `duplicates:` in der gespeicherten Suche greift.
    func matches(_ rule: CollectionRule, duplicateIDs: Set<UUID>) -> Bool {
        rule.matches(tagIDs: Set(tags.map(\.id)), statuses: Set(statusTags.map(\.name)),
                     searchable: { searchableCopy(isDuplicate: duplicateIDs.contains(id)) })
    }
}

extension EraStore {
    /// Legt eine bestaetigte Sammlung an. nil bei leerem/doppeltem Namen oder leerer Regel.
    @discardableResult
    func createCollection(named proposed: String, rule: CollectionRule) -> Pack? {
        guard !rule.isEmpty else { return nil }
        let existing = ((try? allPacks()) ?? []).map(\.name)
        guard case .ok(let name) = CollectionName.validate(proposed, existing: existing) else { return nil }
        let pack = Pack(name: name, confirmed: true)
        pack.rule = rule
        context.insert(pack)
        save()
        return pack
    }

    /// Aendert Name und Regel. false, wenn etwas ungueltig ist; dann bleibt alles unveraendert.
    @discardableResult
    func updateCollection(_ pack: Pack, name proposed: String, rule: CollectionRule) -> Bool {
        let pack = resolve(pack)
        guard !rule.isEmpty else { return false }
        let others = ((try? allPacks()) ?? []).filter { $0.id != pack.id }.map(\.name)
        guard case .ok(let name) = CollectionName.validate(proposed, existing: others) else { return false }
        pack.name = name
        pack.rule = rule
        pack.confirmed = true
        save()
        return true
    }

    /// Legt aus den aktuellen Treffern einer Sammlung eine normale Playlist an (Momentaufnahme).
    @discardableResult
    func playlistFromCollection(_ pack: Pack, songs: [Song]) -> Playlist? {
        let existing = Set(((try? allPlaylists()) ?? []).map { $0.name.lowercased() })
        var name = pack.name
        var n = 2
        while existing.contains(name.lowercased()) { name = "\(pack.name) \(n)"; n += 1 }
        return createPlaylist(named: name, songs: songs)
    }
}

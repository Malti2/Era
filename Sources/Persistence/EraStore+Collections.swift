import Foundation
import SwiftData

// Sammlungen (Packs) anlegen, bearbeiten, loeschen. Namen sind eindeutig, eine Sammlung braucht mindestens eine Bedingung.
extension Pack {
    var rule: CollectionRule { CollectionRule(tagIDs: Set(tagIDs), statusNames: Set(statusNames)) }
}

extension Song {
    func matches(_ rule: CollectionRule) -> Bool {
        rule.matches(tagIDs: Set(tags.map(\.id)), statuses: Set(statusTags.map(\.name)))
    }
}

extension EraStore {
    /// Legt eine bestaetigte Sammlung an. nil bei leerem/doppeltem Namen oder leerer Regel.
    @discardableResult
    func createCollection(named proposed: String, rule: CollectionRule) -> Pack? {
        guard !rule.isEmpty else { return nil }
        let existing = ((try? allPacks()) ?? []).map(\.name)
        guard case .ok(let name) = CollectionName.validate(proposed, existing: existing) else { return nil }
        let pack = Pack(name: name, tagIDs: Array(rule.tagIDs), statusNames: Array(rule.statusNames).sorted(), confirmed: true)
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
        pack.tagIDs = Array(rule.tagIDs)
        pack.statusNames = Array(rule.statusNames).sorted()
        pack.confirmed = true
        save()
        return true
    }
}

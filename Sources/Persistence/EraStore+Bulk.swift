import Foundation
import SwiftData

// Sammelaktionen fuer die Mehrfachauswahl und die Tag-Verwaltung.
extension EraStore {
    func setFavorite(_ value: Bool, for songs: [Song]) {
        for song in songs { resolve(song).isFavorite = value }
        save()
    }

    func add(_ tag: Tag, to songs: [Song]) {
        let tag = resolve(tag)
        for song in songs.map({ resolve($0) }) where !song.tags.contains(where: { $0.id == tag.id }) {
            song.tags.append(tag)
        }
        save()
    }

    func remove(_ tag: Tag, from songs: [Song]) {
        let tag = resolve(tag)
        for song in songs.map({ resolve($0) }) { song.tags.removeAll { $0.id == tag.id } }
        save()
    }

    func deleteSongs(_ songs: [Song]) {
        for song in songs { deleteSong(song) }
    }

    // MARK: Tag-Verwaltung

    /// Renames a personal tag. A name that belongs to another tag merges both into it:
    /// songs, packs and smart filters follow, the old tag disappears.
    @discardableResult
    func renameTag(_ tag: Tag, to proposed: String) -> TagRename {
        let tag = resolve(tag)
        guard !tag.isStatus else { return .invalid }
        let names = ((try? allTags()) ?? []).map(\.name)
        let outcome = TagRename.resolve(proposed, current: tag.name, existing: names)
        switch outcome {
        case .invalid, .unchanged:
            break
        case .rename(let name):
            tag.name = name
            save()
        case .merge(let name):
            guard let target = try? self.tag(named: name), target.id != tag.id else { return .invalid }
            for song in Array(tag.songs) {
                song.tags.removeAll { $0.id == tag.id }
                if !song.tags.contains(where: { $0.id == target.id }) { song.tags.append(target) }
            }
            repoint(tag.id, to: target.id)
            context.delete(tag)
            save()
        }
        return outcome
    }

    /// Deletes a personal tag everywhere, including pack and playlist filters that used it.
    func deleteTagEverywhere(_ tag: Tag) {
        let tag = resolve(tag)
        guard !tag.isStatus else { return }
        repoint(tag.id, to: nil)
        for song in Array(tag.songs) { song.tags.removeAll { $0.id == tag.id } }
        context.delete(tag)
        save()
    }

    /// Personal tags no song carries and no pack or playlist filter refers to.
    func unusedTags() -> [Tag] {
        var referenced = Set<UUID>()
        for pack in (try? allPacks()) ?? [] { referenced.formUnion(pack.tagIDs) }
        for playlist in (try? allPlaylists()) ?? [] { referenced.formUnion(playlist.filterTagIDs) }
        return ((try? allTags()) ?? []).filter { !$0.isStatus && $0.songs.isEmpty && !referenced.contains($0.id) }
    }

    @discardableResult
    func deleteUnusedTags() -> Int {
        let unused = unusedTags()
        for tag in unused { context.delete(tag) }
        if !unused.isEmpty { save() }
        return unused.count
    }

    /// Points pack and playlist filters from `old` to `new` (or just drops `old`).
    private func repoint(_ old: UUID, to new: UUID?) {
        func updated(_ ids: [UUID]) -> [UUID] {
            var result: [UUID] = []
            for id in ids {
                let mapped = id == old ? new : id
                if let mapped, !result.contains(mapped) { result.append(mapped) }
            }
            return result
        }
        for pack in (try? allPacks()) ?? [] where pack.tagIDs.contains(old) { pack.tagIDs = updated(pack.tagIDs) }
        for playlist in (try? allPlaylists()) ?? [] where playlist.filterTagIDs.contains(old) {
            playlist.filterTagIDs = updated(playlist.filterTagIDs)
        }
    }
}

import Foundation
import SwiftData

// Playlist-Aktionen jenseits des Grundgeruests: dauerhaft sortieren und duplizieren.
extension EraStore {
    /// Schreibt die Reihenfolge der gesamten (ungefilterten) Playlist neu.
    func sortPlaylist(_ playlist: Playlist, by order: PlaylistSortOrder) {
        let playlist = resolve(playlist)
        let entries = playlist.sortedEntries
        let rows = entries.map { entry -> PlaylistRow in
            let version = entry.resolvedVersion
            let override = version?.artistOverride ?? ""
            return PlaylistRow(
                id: entry.id,
                title: version?.displayTitle ?? entry.song?.title ?? "",
                artist: override.isEmpty ? (entry.song?.artist ?? "") : override,
                dateAdded: entry.dateAdded,
                duration: version?.duration ?? 0
            )
        }
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, id) in order.ordered(rows).enumerated() {
            if let entry = byID[id], entry.position != index { entry.position = index }
        }
        save()
    }

    /// Kopiert eine Playlist samt Reihenfolge, gewaehlter Versionen und Tag-Filter.
    @discardableResult
    func duplicatePlaylist(_ playlist: Playlist, named name: String) -> Playlist? {
        let source = resolve(playlist)
        guard let copy = createPlaylist(named: name) else { return nil }
        copy.filterTagIDs = source.filterTagIDs
        var position = 0
        for entry in source.sortedEntries {
            guard let song = entry.song else { continue }
            let clone = PlaylistEntry(position: position, song: song, versionID: entry.versionID)
            clone.playlist = copy
            context.insert(clone)
            position += 1
        }
        save()
        return copy
    }
}

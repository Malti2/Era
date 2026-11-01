import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

// CoreSpotlight (Apple-Doku: "Adding your app's content to Spotlight indexes"):
// Songs landen im privaten On-Device-Index und erscheinen in der systemweiten
// Suche. Tipp auf einen Treffer oeffnet Era und spielt den Song (siehe ContentView).
enum SpotlightIndexer {
    private static let domain = "songs"

    struct Entry {
        let id: UUID
        let title: String
        let artist: String
        let album: String
        let keywords: [String]
        let thumbnail: Data?
    }

    static func clearAll() {
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default().deleteAllSearchableItems()
        }
    }

    // Kompletter Neuaufbau des Index: Bibliothek ist klein, das ist der
    // zuverlaessigste Weg gegen verwaiste Treffer nach Loeschungen.
    static func reindex(songs: [Song]) {
        let entries = songs.map(entry(for:))
        Task.detached(priority: .utility) {
            let index = CSSearchableIndex.default()
            do {
                try await index.deleteAllSearchableItems()
                let items = entries.map(item(for:))
                if !items.isEmpty { try await index.indexSearchableItems(items) }
            } catch {
                // Index-Fehler sind nicht kritisch: App funktioniert ohne Spotlight-Treffer.
            }
        }
    }

    /// Aktualisiert nur diese Songs (z. B. nach dem Bearbeiten), ohne den ganzen Index neu zu bauen.
    static func update(songs: [Song]) {
        guard AppSettings.bool(AppSettings.spotlightEnabledKey), !songs.isEmpty else { return }
        let entries = songs.map(entry(for:))
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default().indexSearchableItems(entries.map(item(for:)))
        }
    }

    /// Entfernt geloeschte Songs sofort aus dem Index, damit Spotlight keine toten Treffer zeigt.
    static func remove(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let identifiers = ids.map(\.uuidString)
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers)
        }
    }

    private static func entry(for song: Song) -> Entry {
        var thumb: Data?
        if let artFile = song.primaryVersion?.artworkFile,
           let data = try? Data(contentsOf: LibraryFiles.artworkURL(artFile)) {
            thumb = data
        }
        return Entry(
            id: song.id,
            title: song.title,
            artist: song.displayArtist,
            album: song.album,
            keywords: song.tags.map(\.name) + song.versions.map(\.name) + (song.era.isEmpty ? [] : [song.era]),
            thumbnail: thumb
        )
    }

    private static func item(for entry: Entry) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .audio)
        attrs.title = entry.title
        attrs.artist = entry.artist
        attrs.album = entry.album
        attrs.contentDescription = [entry.artist, entry.album].filter { !$0.isEmpty }.joined(separator: " - ")
        attrs.keywords = entry.keywords
        attrs.thumbnailData = entry.thumbnail
        return CSSearchableItem(uniqueIdentifier: entry.id.uuidString, domainIdentifier: domain, attributeSet: attrs)
    }
}

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
        let entries: [Entry] = songs.map { song in
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
        Task.detached(priority: .utility) {
            let index = CSSearchableIndex.default()
            do {
                try await index.deleteAllSearchableItems()
                let items = entries.map { entry -> CSSearchableItem in
                    let attrs = CSSearchableItemAttributeSet(contentType: .audio)
                    attrs.title = entry.title
                    attrs.artist = entry.artist
                    attrs.album = entry.album
                    attrs.contentDescription = [entry.artist, entry.album].filter { !$0.isEmpty }.joined(separator: " - ")
                    attrs.keywords = entry.keywords
                    attrs.thumbnailData = entry.thumbnail
                    return CSSearchableItem(uniqueIdentifier: entry.id.uuidString, domainIdentifier: domain, attributeSet: attrs)
                }
                if !items.isEmpty { try await index.indexSearchableItems(items) }
            } catch {
                // Index-Fehler sind nicht kritisch: App funktioniert ohne Spotlight-Treffer.
            }
        }
    }
}

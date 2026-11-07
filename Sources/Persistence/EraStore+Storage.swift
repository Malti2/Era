import Foundation
import SwiftData

// Speicher aufraeumen: alternative Versionen gesammelt loeschen (Library Overview -> Free Up Space).
extension EraStore {
    /// Deletes the given versions and their files. A song always keeps at least one version and its
    /// primary version is never removed here. Returns the number of versions actually deleted.
    @discardableResult
    func deleteAlternateVersions(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }
        var deleted = 0
        var touched: [Song] = []
        let playlists = (try? allPlaylists()) ?? []
        for version in (try? allVersions()) ?? [] where ids.contains(version.id) {
            guard let song = version.song, song.versions.count > 1, song.primaryVersion?.id != version.id else { continue }
            VersionFiles.delete(version: version)
            song.versions.removeAll { $0.id == version.id }
            for playlist in playlists {
                for entry in playlist.entries where entry.versionID == version.id { entry.versionID = nil }
            }
            context.delete(version)
            if !touched.contains(where: { $0.id == song.id }) { touched.append(song) }
            deleted += 1
        }
        guard deleted > 0 else { return 0 }
        save()
        SpotlightIndexer.update(songs: touched)
        return deleted
    }
}

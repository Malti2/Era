import Foundation

// Eigenes Cover pro Version (ueberschreibt das eingebettete Cover der Datei).
extension EraStore {
    /// Speichert bereits aufbereitete Bilddaten als Cover der Version und raeumt das alte weg.
    /// Der Dateiname aendert sich bei jedem Wechsel, damit kein veraltetes Bild aus dem Cache kommt.
    @discardableResult
    func setArtwork(_ data: Data, for version: SongVersion, directory: URL = LibraryFiles.artworkDir) -> Bool {
        let version = resolve(version)
        let name = "\(version.id.uuidString)-\(UUID().uuidString.prefix(8)).img"
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            Persistence.log.error("artwork write failed: \(error.localizedDescription)")
            return false
        }
        removeArtworkFile(version.artworkFile, in: directory)
        version.artworkFile = name
        save()
        return true
    }

    /// Entfernt das Cover der Version; angezeigt wird dann wieder die generierte Disc.
    func clearArtwork(for version: SongVersion, directory: URL = LibraryFiles.artworkDir) {
        let version = resolve(version)
        removeArtworkFile(version.artworkFile, in: directory)
        version.artworkFile = nil
        save()
    }

    private func removeArtworkFile(_ file: String?, in directory: URL) {
        guard let file else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        ArtworkCache.evict(file)
    }
}

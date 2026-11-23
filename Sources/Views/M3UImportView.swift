import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// M3U-Import als wiederverwendbarer Knopf: steckt in "Backup & Wartung" und in der
// Playlists-Sektion der Library. Picker, Abgleich und Ergebnis-Alert leben hier,
// damit beide Stellen denselben Ablauf haben.
struct M3UImportButton: View {
    var songs: [Song]
    var playlists: [Playlist]
    @EnvironmentObject private var store: EraStore
    @State private var showPicker = false
    @State private var alert: ImportAlert?

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        Button { showPicker = true } label: {
            Label("Import Playlist (M3U)", systemImage: "square.and.arrow.down")
        }
        // UIKit-Picker statt .fileImporter: Letzterer schliesst auf Geraeten oft nicht (siehe DocumentPicker).
        .sheet(isPresented: $showPicker) {
            DocumentPicker(contentTypes: m3uTypes, onPicked: { urls in
                showPicker = false
                if let url = urls.first { importM3U(url) }
            }, onCancel: { showPicker = false })
        }
        .alert(item: $alert) { Alert(title: Text($0.title), message: Text($0.message), dismissButton: .default(Text("OK"))) }
    }

    private var m3uTypes: [UTType] {
        [UTType(filenameExtension: "m3u") ?? .text, UTType(filenameExtension: "m3u8") ?? .text]
    }

    private func m3uText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1)
    }

    private func importM3U(_ url: URL) {
        guard let text = m3uText(url) else {
            alert = ImportAlert(title: String(localized: "Couldn't Read Playlist"),
                                message: String(localized: "This file doesn't look like a playlist."))
            return
        }
        let entries = PlaylistM3UImport.parse(text)
        guard !entries.isEmpty else {
            alert = ImportAlert(title: String(localized: "The playlist is empty."), message: "")
            return
        }
        let library = songs.map { song in
            PlaylistM3UImport.LibraryTrack(id: song.id, title: song.title, artist: song.artist,
                                           fileNames: song.versions.map(\.fileName))
        }
        let result = PlaylistM3UImport.match(entries, against: library)
        guard !result.matched.isEmpty else {
            alert = ImportAlert(title: String(localized: "No Songs Matched"),
                                message: String(localized: "Not found: \(missingNames(result.unmatched))"))
            return
        }
        let matchedSongs = result.matched.compactMap { id in songs.first { $0.id == id } }
        let name = uniquePlaylistName(from: url.deletingPathExtension().lastPathComponent)
        store.createPlaylist(named: name, songs: matchedSongs)
        var message = String(localized: "Added \(result.matched.count) of \(entries.count) tracks.")
        if !result.unmatched.isEmpty {
            message += "\n" + String(localized: "Not found: \(missingNames(result.unmatched))")
        }
        alert = ImportAlert(title: String(localized: "Playlist Imported"), message: message)
    }

    /// "Artist - Titel", max. 5 Eintraege, danach "…".
    private func missingNames(_ unmatched: [M3UEntry]) -> String {
        let names = unmatched.prefix(5).map { $0.artist.isEmpty ? $0.title : "\($0.artist) - \($0.title)" }
        return names.joined(separator: ", ") + (unmatched.count > 5 ? ", …" : "")
    }

    /// Playlist-Name aus dem Dateinamen; bei Kollision "Name 2", "Name 3", …
    private func uniquePlaylistName(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? String(localized: "Imported Playlist") : trimmed
        guard playlists.contains(where: { $0.name == name }) else { return name }
        var number = 2
        while playlists.contains(where: { $0.name == "\(name) \(number)" }) { number += 1 }
        return "\(name) \(number)"
    }
}

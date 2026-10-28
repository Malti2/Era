import SwiftUI
import SwiftData

// Ein zentraler Einstieg fuer "Zur Playlist hinzufuegen": Kontextmenues loesen nur
// den Koordinator aus, das Sheet haengt einmal in ContentView (ein Sheet innerhalb
// eines Kontextmenues verschwindet mit dem Menue).
@MainActor
final class PlaylistPickerCoordinator: ObservableObject {
    @Published var songs: [Song] = []
    var isPresented: Bool {
        get { !songs.isEmpty }
        set { if !newValue { songs = [] } }
    }
    func present(_ songs: [Song]) { self.songs = songs }
}

struct PlaylistPickerSheet: View {
    let songs: [Song]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @Query(sort: \Playlist.dateAdded, order: .reverse) private var playlists: [Playlist]
    @AppStorage(AppSettings.hapticsEnabledKey) private var haptics = true
    @State private var showNew = false
    @State private var newName = ""

    private var heading: String {
        songs.count == 1 ? (songs.first?.title ?? "") : String(localized: "\(songs.count) songs")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showNew = true } label: { Label("New Playlist", systemImage: "plus") }
                }
                if !playlists.isEmpty {
                    Section {
                        ForEach(playlists) { playlist in
                            let contained = songs.allSatisfy { song in playlist.entries.contains { $0.song?.id == song.id } }
                            Button { add(to: playlist) } label: {
                                HStack(spacing: 12) {
                                    PlaylistMosaic(playlist: playlist).frame(width: 48, height: 48)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name).foregroundStyle(.primary)
                                        Text("\(playlist.entries.count) tracks").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if contained { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                                }
                            }
                            .disabled(contained)
                            .accessibilityHint(contained ? Text("Already in this playlist") : Text(""))
                        }
                    } header: { Text(heading) }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .alert("New Playlist", isPresented: $showNew) {
                TextField("Name", text: $newName)
                Button("Erstellen") {
                    if let playlist = store.createPlaylist(named: newName, songs: songs) { finish(playlist) }
                    newName = ""
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(to playlist: Playlist) {
        store.addSongs(songs, to: playlist)
        finish(playlist)
    }

    private func finish(_ playlist: Playlist) {
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        dismiss()
    }
}

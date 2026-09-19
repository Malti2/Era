import SwiftUI
import SwiftData

struct SearchView: View {
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine
    @Query private var songs: [Song]
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [Song] {
        guard !query.isEmpty else { return [] }
        return songs.filter { song in
            song.title.localizedCaseInsensitiveContains(query)
            || song.displayArtist.localizedCaseInsensitiveContains(query)
            || song.album.localizedCaseInsensitiveContains(query)
            || song.era.localizedCaseInsensitiveContains(query)
            || song.tags.contains { $0.name.localizedCaseInsensitiveContains(query) }
            || song.versions.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ContentUnavailableView {
                        Label("Search Your Library", systemImage: "magnifyingglass")
                    } description: {
                        Text("Search by title, artist, album, tag, or version.")
                    } actions: {
                        Text("Try “Demo”, an artist, or a version name like “OG”.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { song in
                        HStack(spacing: 10) {
                            Button {
                                if let version = song.primaryVersion { player.play(version, from: results.compactMap(\.primaryVersion)); showNowPlaying = true }
                            } label: { SongRow(song: song, version: nil, isCurrent: player.current?.song?.id == song.id) }
                            .buttonStyle(.plain)
                            NavigationLink { SongDetailView(song: song, showNowPlaying: $showNowPlaying) } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .contextMenu { SongContextMenu(song: song, showNowPlaying: $showNowPlaying) }
                    }.listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title, artist, album, tag, version")
            .searchFocused($focused)
            .onAppear { focused = true }
        }
    }
}

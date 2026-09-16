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
                        Label("Keine letzten Suchanfragen", systemImage: "magnifyingglass")
                    } description: {
                        Text("Deine letzten Suchanfragen werden hier angezeigt.")
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { song in
                        NavigationLink { SongDetailView(song: song, showNowPlaying: $showNowPlaying) } label: {
                            SongRow(song: song, version: nil, isCurrent: player.current?.song?.id == song.id)
                        }
                        .contextMenu { SongContextMenu(song: song, showNowPlaying: $showNowPlaying) }
                    }.listStyle(.plain)
                }
            }
            .navigationTitle("Suche")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Künstler:in, Titel, Album, Tag")
            .searchFocused($focused)
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--era-search-preview") && false {
                    Task { try? await Task.sleep(nanoseconds: 450_000_000); focused = true }
                }
            }
        }
    }
}

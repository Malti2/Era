import SwiftUI
import SwiftData

struct SearchView: View {
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine
    @Query private var songs: [Song]
    @State private var query = ""
    @State private var recents = UserDefaults.standard.stringArray(forKey: AppSettings.recentSearchesKey) ?? []
    @FocusState private var focused: Bool

    private struct Entry: Identifiable {
        let song: Song
        let hit: SearchHit
        var id: UUID { song.id }
    }

    private var results: [Entry] {
        let hits = SongSearch.search(query, in: songs.map(\.searchable))
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return hits.compactMap { hit in byID[hit.id].map { Entry(song: $0, hit: hit) } }
    }

    private var suggestions: [SearchSuggestion] { SearchSuggestions.make(from: songs.map(\.searchable)) }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    idleState
                } else {
                    let found = results
                    if found.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        resultList(found)
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title, artist, album, tag, version")
            .searchFocused($focused)
            .onSubmit(of: .search) { remember(query) }
            .onAppear { focused = true }
        }
    }

    private func resultList(_ found: [Entry]) -> some View {
        let queue = found.compactMap(\.song.primaryVersion)
        return List(found) { entry in
            let song = entry.song
            HStack(spacing: 10) {
                Button {
                    remember(query)
                    if let version = song.primaryVersion { player.play(version, from: queue); showNowPlaying = true }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        SongRow(song: song, version: nil, isCurrent: player.current?.song?.id == song.id)
                        if let hint = matchHint(entry.hit) {
                            Text(hint).font(.caption2).foregroundStyle(.tertiary).padding(.leading, 62)
                        }
                    }
                }
                .buttonStyle(.plain)
                NavigationLink { SongDetailView(song: song, showNowPlaying: $showNowPlaying) } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Song Details")
            }
            .contextMenu { SongContextMenu(song: song, showNowPlaying: $showNowPlaying) }
        }
        .listStyle(.plain)
    }

    /// Nur wenn der Treffer nicht schon aus Titel/Artist sichtbar ist (z.B. Tag, Version).
    private func matchHint(_ hit: SearchHit) -> String? {
        guard hit.matchedFields.isDisjoint(with: [.title, .artist]) else { return nil }
        let names = hit.matchedFields.sorted { $0.sortOrder < $1.sortOrder }.map(\.label)
        guard !names.isEmpty else { return nil }
        return String(localized: "Found in \(names.joined(separator: ", "))")
    }

    @ViewBuilder private var idleState: some View {
        if songs.isEmpty {
            ContentUnavailableView {
                Label("Search Your Library", systemImage: "magnifyingglass")
            } description: {
                Text("Search by title, artist, album, tag, or version.")
            }
        } else {
            List {
                if !recents.isEmpty {
                    Section {
                        ForEach(recents, id: \.self) { recent in
                            Button { query = recent } label: {
                                Label(recent, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                            }
                        }
                        .onDelete { offsets in
                            recents.remove(atOffsets: offsets)
                            UserDefaults.standard.set(recents, forKey: AppSettings.recentSearchesKey)
                        }
                    } header: {
                        HStack {
                            Text("Recent Searches")
                            Spacer()
                            Button("Clear") {
                                recents = []
                                UserDefaults.standard.removeObject(forKey: AppSettings.recentSearchesKey)
                            }
                            .font(.footnote).textCase(nil)
                        }
                    }
                }
                if !suggestions.isEmpty {
                    Section("Quick Filters") {
                        ForEach(suggestions) { suggestion in
                            Button { query = suggestion.query } label: {
                                HStack {
                                    Text(suggestion.label).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(suggestion.count)").foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                }
                Section {
                    Text("Tip: combine words, or use tag:, status:, year:2018-2020, version: and fav.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func remember(_ text: String) {
        recents = RecentSearches.adding(text, to: recents)
        UserDefaults.standard.set(recents, forKey: AppSettings.recentSearchesKey)
    }
}

private extension SearchField {
    var label: String {
        switch self {
        case .title: String(localized: "Title")
        case .artist: String(localized: "Artist")
        case .album: String(localized: "Album")
        case .era: String(localized: "Era / Project")
        case .tag: String(localized: "Tags")
        case .status: String(localized: "Status")
        case .version: String(localized: "Versions")
        }
    }
    var sortOrder: Int {
        switch self {
        case .title: 0
        case .artist: 1
        case .album: 2
        case .era: 3
        case .status: 4
        case .tag: 5
        case .version: 6
        }
    }
}

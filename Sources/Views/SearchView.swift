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

    private func results(in snapshot: [SearchableSong]) -> [Entry] {
        let hits = SongSearch.search(query, in: snapshot)
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return hits.compactMap { hit in byID[hit.id].map { Entry(song: $0, hit: hit) } }
    }


    var body: some View {
        // Ein Schnappschuss pro Render: Treffer, Vorschlaege und Vervollstaendigung teilen sich ihn (grosse Bibliotheken).
        let snapshot = songs.map(\.searchable)
        return NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    idleState(SearchSuggestions.make(from: snapshot))
                } else {
                    let found = results(in: snapshot)
                    if found.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        resultList(found)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { completionBar(SearchCompletion.make(for: query, songs: snapshot)) }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title, artist, album, tag, version")
            .searchFocused($focused)
            .onSubmit(of: .search) { remember(query) }
            .onAppear { focused = true }
        }
    }

    private func resultList(_ found: [Entry]) -> some View {
        let queue = found.compactMap(\.song.primaryVersion)
        return List {
            Section {
                ForEach(found) { entry in resultRow(entry, queue: queue) }
            } header: {
                Text("\(found.count) songs").textCase(nil)
            }
        }
        .listStyle(.plain)
    }

    /// Antippbare Ergaenzungen fuer das letzte Wort (`ta` -> `tag:`, `tag:sy` -> `tag:synth`).
    @ViewBuilder private func completionBar(_ options: [SearchSuggestion]) -> some View {
        if !options.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        Button { query = option.query.hasSuffix(":") ? option.query : option.query + " " } label: {
                            Text(option.label).font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal).padding(.vertical, 6)
            }
            .background(.bar)
        }
    }

    private func resultRow(_ entry: Entry, queue: [SongVersion]) -> some View {
        let song = entry.song
        return Group {
            HStack(spacing: 10) {
                Button {
                    remember(query)
                    if let version = song.primaryVersion { player.play(version, from: queue); showNowPlaying = true }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        SongRow(song: song, version: nil, isCurrent: player.current?.song?.id == song.id)
                        if let snippet = noteSnippet(entry) {
                            Label(snippet, systemImage: "note.text").labelStyle(.titleAndIcon)
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).padding(.leading, 62)
                        } else if let hint = matchHint(entry.hit) {
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
    }

    /// Ausschnitt aus Notiz/Marker, wenn der Treffer nur dort liegt.
    private func noteSnippet(_ entry: Entry) -> String? {
        guard entry.hit.matchedFields.contains(.note),
              entry.hit.matchedFields.isDisjoint(with: [.title, .artist]) else { return nil }
        let labels = entry.song.versions.flatMap { $0.markers.map(\.label) }
        return NoteSnippet.excerpt(in: [entry.song.notes] + labels, terms: SongSearchQuery(query).terms)
    }

    /// Nur wenn der Treffer nicht schon aus Titel/Artist sichtbar ist (z.B. Tag, Version).
    private func matchHint(_ hit: SearchHit) -> String? {
        guard hit.matchedFields.isDisjoint(with: [.title, .artist]) else { return nil }
        let names = hit.matchedFields.sorted { $0.sortOrder < $1.sortOrder }.map(\.label)
        guard !names.isEmpty else { return nil }
        return String(localized: "Found in \(names.joined(separator: ", "))")
    }

    @ViewBuilder private func idleState(_ suggestions: [SearchSuggestion]) -> some View {
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
                    Text("Tip: combine words, or use tag:, status:, year:2018-2020, version: and fav. Prefix with - to exclude, e.g. -tag:demo. Also try has:notes, plays:>5 and unplayed.")
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
        case .note: String(localized: "Notes")
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
        case .note: 7
        }
    }
}

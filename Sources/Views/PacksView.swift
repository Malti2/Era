import SwiftUI
import SwiftData

// Collections are saved and automatic filters across tags and status.
struct PacksView: View {
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var store: EraStore
    @Query private var packs: [Pack]
    @Query private var songs: [Song]
    @Query private var tags: [Tag]
    @State private var editor: CollectionEditorTarget?
    @State private var packToDelete: Pack?

    private var confirmed: [Pack] { packs.filter { $0.confirmed } }
    private var suggested: [Pack] { packs.filter { !$0.confirmed } }

    // Dynamische Packs, nur lokal berechnet (Spec 7.1)
    private var dynamicPacks: [(String, String, [Song])] {
        var result: [(String, String, [Song])] = []
        let mostPlayed = songs.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }
        if !mostPlayed.isEmpty { result.append(("Most Played", "chart.bar.fill", Array(mostPlayed.prefix(25)))) }
        let recent = Array(songs.sorted { $0.dateAdded > $1.dateAdded }.prefix(25))
        if !recent.isEmpty { result.append(("Recently Added", "clock.fill", recent)) }
        let favs = songs.filter(\.isFavorite)
        if !favs.isEmpty { result.append(("Favorites", "heart.fill", favs)) }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if !dynamicPacks.isEmpty {
                    Section("Automatic") {
                        ForEach(dynamicPacks, id: \.0) { name, icon, packSongs in
                            NavigationLink {
                                SongListView(title: name, songs: packSongs, showNowPlaying: $showNowPlaying)
                            } label: {
                                Label("\(name) (\(packSongs.count))", systemImage: icon)
                            }
                        }
                    }
                }

                if !confirmed.isEmpty {
                    Section("My Collections") {
                        ForEach(confirmed) { pack in
                            NavigationLink {
                                PackDetailView(pack: pack, showNowPlaying: $showNowPlaying)
                            } label: {
                                Label("\(pack.name) (\(matching(pack).count))", systemImage: "square.stack.fill")
                            }
                            .swipeActions {
                                Button(role: .destructive) { packToDelete = pack } label: { Label("Delete", systemImage: "trash") }
                                Button { editor = .edit(pack) } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                            }
                            .contextMenu {
                                Button { editor = .edit(pack) } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) { packToDelete = pack } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }

                if !suggested.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggested) { pack in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label("\(pack.name) (\(matching(pack).count))", systemImage: "square.stack")
                                    Text(suggestionReason(pack)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    pack.confirmed = true
                                    store.save()
                                } label: {
                                    Text("Add").font(.subheadline.weight(.medium))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .swipeActions {
                                Button(role: .destructive) { store.dismissPackSuggestion(pack) } label: {
                                    Label("Verwerfen", systemImage: "xmark")
                                }
                            }
                        }
                    }
                }

                if confirmed.isEmpty && suggested.isEmpty && dynamicPacks.isEmpty {
                    ContentUnavailableView {
                        Label("No Collections Yet", systemImage: "square.stack")
                    } description: {
                        Text("Collections are saved filters that update automatically when you edit tags or status.")
                    } actions: {
                        Text("Add tags to songs to get suggestions here.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editor = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Collection")
                }
            }
            .sheet(item: $editor) { target in
                CollectionEditorView(pack: target.pack)
            }
            .confirmationDialog("Delete Collection?", isPresented: Binding(get: { packToDelete != nil }, set: { if !$0 { packToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete Collection", role: .destructive) {
                    if let pack = packToDelete { store.deletePack(pack) }
                    packToDelete = nil
                }
                Button("Cancel", role: .cancel) { packToDelete = nil }
            } message: {
                Text("Songs stay in your library.")
            }
        }
    }

    private func suggestionReason(_ pack: Pack) -> String {
        if let status = pack.statusNames.first { return String(localized: "Suggested from status: \(status)") }
        if let tagID = pack.tagIDs.first, let tag = tags.first(where: { $0.id == tagID }) { return String(localized: "Suggested from tag: \(tag.name)") }
        return String(localized: "Suggested from your library")
    }

    func matching(_ pack: Pack) -> [Song] {
        let rule = pack.rule
        return songs.filter { $0.matches(rule) }
    }
}

/// Ziel des Sammlungs-Editors: neu oder bestehend.
enum CollectionEditorTarget: Identifiable {
    case new
    case edit(Pack)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let pack): pack.id.uuidString
        }
    }

    var pack: Pack? {
        if case .edit(let pack) = self { return pack }
        return nil
    }
}

struct PackDetailView: View {
    let pack: Pack
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine
    @Query private var songs: [Song]

    @EnvironmentObject private var store: EraStore
    @State private var showEditor = false
    @State private var savedPlaylistName: String?
    @AppStorage(AppSettings.collectionSortKey) private var sortRaw = LibrarySort.recent.rawValue

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }

    private var matching: [Song] {
        let rule = pack.rule
        let hits = songs.filter { $0.matches(rule) }
        let byID = Dictionary(hits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return sort.ordered(hits.map(\.sortRow)).compactMap { byID[$0] }
    }

    private func count(_ status: String) -> Int {
        matching.filter { $0.statusTags.contains { $0.name == status } }.count
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    stat("Songs", matching.count)
                    stat("Released", count("Released"))
                    stat("Unreleased", count("Unreleased"))
                    stat("Leaks", count("Leak"))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                Button {
                    let versions = matching.compactMap(\.primaryVersion)
                    if let first = versions.first { player.play(first, from: versions) }
                } label: { Label("Play All", systemImage: "play.fill") }
                .disabled(matching.isEmpty)
                Button {
                    player.playShuffled(matching.compactMap(\.primaryVersion))
                } label: { Label("Shuffle", systemImage: "shuffle") }
                .disabled(matching.isEmpty)
                ForEach(matching) { song in
                    NavigationLink {
                        SongDetailView(song: song, showNowPlaying: $showNowPlaying)
                    } label: {
                        SongRow(song: song, version: nil)
                    }
                }
            }
        }
        .navigationTitle(pack.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: Binding(get: { sort }, set: { sortRaw = $0.rawValue })) {
                        ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                    }
                    Divider()
                    Button { savePlaylist() } label: { Label("Save as Playlist", systemImage: "music.note.list") }
                        .disabled(matching.isEmpty)
                    Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showEditor) { CollectionEditorView(pack: pack) }
        .alert("Playlist Created", isPresented: Binding(get: { savedPlaylistName != nil }, set: { if !$0 { savedPlaylistName = nil } })) {
            Button("OK", role: .cancel) { savedPlaylistName = nil }
        } message: {
            Text("“\(savedPlaylistName ?? "")” is now in your playlists. It will not change when the collection does.")
        }
    }

    private func savePlaylist() {
        if let playlist = store.playlistFromCollection(pack, songs: matching) { savedPlaylistName = playlist.name }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore
    @Query private var tags: [Tag]
    @State private var showAddSongs = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var editOrder = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    private var filteredEntries: [PlaylistEntry] {
        let active = playlist.filterTagIDs
        guard !active.isEmpty else { return playlist.sortedEntries }
        return playlist.sortedEntries.filter { entry in
            guard let song = entry.song else { return false }
            return active.allSatisfy { id in song.tags.contains { $0.id == id } }
        }
    }

    private var usedTags: [Tag] {
        let ids = Set(playlist.sortedEntries.compactMap(\.song).flatMap { $0.tags.map(\.id) })
        return tags.filter { ids.contains($0.id) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                if !usedTags.isEmpty { filters.padding(.bottom, 10) }
                Divider().padding(.horizontal, 18)
                ForEach(filteredEntries) { entry in
                    if let song = entry.song {
                        PlaylistEntryRow(playlist: playlist, entry: entry, song: song, editingOrder: editOrder)
                        Divider().padding(.leading, 82)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameText = playlist.name; showRename = true } label: { Label("Rename Playlist", systemImage: "pencil") }
                    Button { editOrder.toggle() } label: { Label(editOrder ? "Done Editing" : "Edit Order", systemImage: "arrow.up.arrow.down") }
                    Button { showAddSongs = true } label: { Label("Add Songs", systemImage: "plus") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Playlist", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sheet(isPresented: $showAddSongs) { AddToPlaylistSheet(playlist: playlist) }
        .alert("Rename Playlist", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Save") { let name = renameText.trimmingCharacters(in: .whitespaces); if !name.isEmpty { playlist.name = name; store.save() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete Playlist?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) { store.deletePlaylist(playlist); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Songs stay in your library.") }
    }

    private var header: some View {
        VStack(spacing: 14) {
            PlaylistMosaic(playlist: playlist)
                .frame(width: 250, height: 250)
                .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
                .padding(.top, 16)
            VStack(spacing: 4) {
                Text(playlist.name).font(.title2.bold()).multilineTextAlignment(.center)
                Text("Era").font(.title3).foregroundStyle(.tint)
                Text(playlist.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Button { player.playShuffled(filteredEntries.compactMap(\.resolvedVersion)) } label: {
                    Image(systemName: "shuffle").font(.title2).frame(width: 52, height: 52)
                        .background(.thinMaterial, in: .circle)
                }
                Button {
                    let versions = filteredEntries.compactMap(\.resolvedVersion)
                    if let first = versions.first { player.play(first, from: versions); showNowPlaying = true }
                } label: {
                    Label("Wiedergeben", systemImage: "play.fill")
                        .font(.headline).padding(.horizontal, 25).frame(height: 52)
                        .background(Color.accentColor, in: .capsule).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.bottom, 18)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, label: "All")
                ForEach(usedTags) { tag in filterChip(tag.id, label: tag.name) }
            }.padding(.horizontal, 18)
        }
    }

    private func filterChip(_ tagID: UUID?, label: String) -> some View {
        let active = tagID == nil ? playlist.filterTagIDs.isEmpty : playlist.filterTagIDs.contains(tagID!)
        return Button {
            if let tagID {
                if playlist.filterTagIDs.contains(tagID) { playlist.filterTagIDs.removeAll { $0 == tagID } }
                else { playlist.filterTagIDs.append(tagID) }
            } else { playlist.filterTagIDs = [] }
            store.save()
        } label: {
            Text(label).font(.subheadline.weight(.medium)).padding(.horizontal, 13).padding(.vertical, 7)
                .background(active ? Color.accentColor : Color(.tertiarySystemFill), in: .capsule)
                .foregroundStyle(active ? .white : .primary)
        }.buttonStyle(.plain)
    }
}

struct PlaylistMosaic: View {
    let playlist: Playlist
    private var entries: [PlaylistEntry] { Array(playlist.sortedEntries.prefix(4)) }
    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let side = (proxy.size.width - gap) / 2
            LazyVGrid(columns: [.init(.fixed(side), spacing: gap), .init(.fixed(side), spacing: gap)], spacing: gap) {
                ForEach(0..<4, id: \.self) { i in
                    if i < entries.count, let song = entries[i].song {
                        Artwork(song: song, version: entries[i].resolvedVersion, radius: 0)
                            .frame(width: side, height: side).clipped()
                    } else {
                        Rectangle().fill(Color(.secondarySystemFill))
                            .overlay { Image(systemName: "music.note").foregroundStyle(.tertiary) }
                            .frame(width: side, height: side)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PlaylistEntryRow: View {
    let playlist: Playlist
    let entry: PlaylistEntry
    let song: Song
    var editingOrder: Bool = false
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore
    @State private var showDrawer = false
    private var version: SongVersion? { entry.resolvedVersion }

    var body: some View {
        HStack(spacing: 12) {
            Artwork(song: song, version: version, radius: 6).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(version?.displayTitle ?? song.title).font(.body).lineLimit(1)
                    if song.tags.contains(where: { $0.name == "Explicit" }) {
                        Text("E").font(.caption2.bold()).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(version?.displayArtist ?? song.displayArtist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if player.current?.id == version?.id { Image(systemName: "waveform").foregroundStyle(.tint) }
            if editingOrder { Image(systemName: "line.3.horizontal").foregroundStyle(.secondary) }
            Menu {
                Button { if let v = version { player.playNext(v) } } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { if let v = version { player.playLater(v) } } label: { Label("Add to End", systemImage: "text.line.last.and.arrowtriangle.forward") }
                Button { showDrawer = true } label: { Label("Choose Version", systemImage: "square.stack") }
                Divider()
                Button(role: .destructive) { store.removeEntry(entry, from: playlist) } label: { Label("Entfernen", systemImage: "minus.circle") }
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 44) }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let v = version { player.play(v, from: playlist.sortedEntries.compactMap(\.resolvedVersion)) }
        }
        .sheet(isPresented: $showDrawer) { VersionDrawer(song: song) }
    }
}

struct AddToPlaylistSheet: View {
    let playlist: Playlist
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @Query(sort: \Song.title) private var songs: [Song]
    @State private var search = ""
    @State private var selected: Set<UUID> = []
    @State private var onlyMissing = true
    private var existingSongIDs: Set<UUID> { Set(playlist.entries.compactMap(\.song?.id)) }
    private var filtered: [Song] {
        songs.filter { song in
            (!onlyMissing || !existingSongIDs.contains(song.id)) &&
            (search.isEmpty || song.title.localizedCaseInsensitiveContains(search) || song.artist.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Not Yet Included", isOn: $onlyMissing)
                }
                ForEach(filtered) { song in
                    Button {
                        if selected.contains(song.id) { selected.remove(song.id) } else { selected.insert(song.id) }
                    } label: {
                        HStack {
                            SongRow(song: song, version: nil)
                            Image(systemName: selected.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(song.id) ? Color.accentColor : .secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            .listStyle(.plain).searchable(text: $search, prompt: "Search Songs")
            .navigationTitle("Add Songs").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Add (\(selected.count))") {
                    for song in songs where selected.contains(song.id) { store.appendEntry(song: song, version: song.primaryVersion, to: playlist) }
                    dismiss()
                }.eraProminentButton().disabled(selected.isEmpty).padding().background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

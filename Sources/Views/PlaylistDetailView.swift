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

    private var isFiltered: Bool { !playlist.filterTagIDs.isEmpty }

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
        let entries = filteredEntries
        let queue = entries.compactMap(\.resolvedVersion)
        List {
            header(queue: queue)
                .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
            if !usedTags.isEmpty {
                filters
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            if entries.isEmpty {
                emptyHint.listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            ForEach(entries) { entry in
                if let song = entry.song {
                    PlaylistEntryRow(playlist: playlist, entry: entry, song: song, queue: queue)
                }
            }
            .onMove(perform: isFiltered ? nil : { source, destination in
                store.moveEntries(in: playlist, from: source, to: destination)
            })
            .onDelete { offsets in
                for index in offsets { store.removeEntry(entries[index], from: playlist) }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(editOrder ? .active : .inactive))
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameText = playlist.name; showRename = true } label: { Label("Rename Playlist", systemImage: "pencil") }
                    Button { editOrder.toggle() } label: { Label(editOrder ? "Done Editing" : "Edit Order", systemImage: "arrow.up.arrow.down") }
                        .disabled(isFiltered || playlist.entries.count < 2)
                    Button { showAddSongs = true } label: { Label("Add Songs", systemImage: "plus") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Playlist", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showAddSongs) { AddToPlaylistSheet(playlist: playlist) }
        .alert("Rename Playlist", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Save") { store.renamePlaylist(playlist, to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete Playlist?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) { store.deletePlaylist(playlist); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Songs stay in your library.") }
        .onChange(of: playlist.filterTagIDs) { _, filter in if !filter.isEmpty { editOrder = false } }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Text(playlist.entries.isEmpty ? "This playlist is empty." : "No songs match this filter.")
                .foregroundStyle(.secondary)
            if playlist.entries.isEmpty {
                Button { showAddSongs = true } label: { Label("Add Songs", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    private func header(queue: [SongVersion]) -> some View {
        VStack(spacing: 14) {
            PlaylistMosaic(playlist: playlist)
                .frame(width: 250, height: 250)
                .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
                .padding(.top, 16)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(playlist.name).font(.title2.bold()).multilineTextAlignment(.center)
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Button { player.playShuffled(queue) } label: {
                    Image(systemName: "shuffle").font(.title2).frame(width: 52, height: 52)
                        .background(.thinMaterial, in: .circle)
                }
                .accessibilityLabel("Shuffle")
                Button {
                    if let first = queue.first { player.play(first, from: queue); showNowPlaying = true }
                } label: {
                    Label("Wiedergeben", systemImage: "play.fill")
                        .font(.headline).padding(.horizontal, 25).frame(height: 52)
                        .background(Color.accentColor, in: .capsule).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(queue.isEmpty)
            .opacity(queue.isEmpty ? 0.4 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18).padding(.bottom, 12)
    }

    private var summary: String {
        let count = playlist.entries.count
        guard count > 0 else { return String(localized: "\(count) tracks") }
        return String(localized: "\(count) tracks") + " · " + TimeFormatting.spoken(playlist.totalDuration)
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
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
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
    /// Versions in the order currently shown (respects the active tag filter).
    let queue: [SongVersion]
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
                            .accessibilityLabel("Explicit")
                    }
                }
                Text(version?.displayArtist ?? song.displayArtist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            if player.current?.id == version?.id { Image(systemName: "waveform").foregroundStyle(.tint) }
            Menu {
                Button { if let v = version { player.playNext(v) } } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { if let v = version { player.playLater(v) } } label: { Label("Add to End", systemImage: "text.line.last.and.arrowtriangle.forward") }
                Button { showDrawer = true } label: { Label("Choose Version", systemImage: "square.stack") }
                Divider()
                Button(role: .destructive) { store.removeEntry(entry, from: playlist) } label: { Label("Entfernen", systemImage: "minus.circle") }
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 44) }
            .buttonStyle(.borderless)
            .accessibilityLabel("More")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let v = version { player.play(v, from: queue) }
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
            (search.isEmpty || !SongSearch.search(search, in: [song.searchable]).isEmpty)
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
                    store.addSongs(songs.filter { selected.contains($0.id) }, to: playlist)
                    dismiss()
                }.eraProminentButton().disabled(selected.isEmpty).padding().background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

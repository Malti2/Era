import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum LibrarySection: String, CaseIterable, Identifiable {
    case songs = "Songs", artists = "Artists", albums = "Albums", playlists = "Playlists", versions = "Versions"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .songs: return "music.note"
        case .artists: return "person.fill"
        case .albums: return "square.stack"
        case .playlists: return "music.note.list"
        case .versions: return "opticaldisc"
        }
    }
}

struct LibraryView: View {
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var store: EraStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var importer: ImportManager
    @EnvironmentObject private var playlistPicker: PlaylistPickerCoordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.dateAdded, order: .reverse) private var songs: [Song]
    @Query private var playlists: [Playlist]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @AppStorage(AppSettings.librarySectionKey) private var sectionRaw = LibrarySection.songs.rawValue
    @AppStorage(AppSettings.librarySortKey) private var sortRaw = LibrarySort.recent.rawValue
    @AppStorage(AppSettings.libraryFilterKey) private var filterRaw = ""
    @State private var showImporter = false
    @State private var showFolderImporter = false
    @State private var showSettings = false
    @State private var newPlaylistName = ""
    @State private var showNewPlaylist = false
    @State private var demoSongSheet = false
    @State private var demoPlaylistSheet = false
    @State private var demoSectionOnly = false
    @State private var showSmartPlaylist = false
    @State private var songToDelete: Song?
    @State private var selecting = false
    @State private var selection = BulkSelection()
    @State private var showBulkTags = false
    @State private var confirmBulkDelete = false
    @State private var playlistToDelete: Playlist?
    private let demoForceSmartPlaylist: Bool

    init(showNowPlaying: Binding<Bool>) {
        _showNowPlaying = showNowPlaying
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--era-settings") { _showSettings = State(initialValue: true) }
        if args.contains("--era-picker-test") { _showImporter = State(initialValue: true) }
        if args.contains("--era-playlists") { _sectionRaw = AppStorage(wrappedValue: LibrarySection.playlists.rawValue, AppSettings.librarySectionKey); _demoSectionOnly = State(initialValue: true) }
        if args.contains("--era-song") { _demoSongSheet = State(initialValue: true) }
        if args.contains("--era-playlist") { _demoPlaylistSheet = State(initialValue: true) }
        // Screenshot mode: the simulator has no Apple Intelligence, so the demo
        // flag force-shows the entry point and can open the sheet directly.
        demoForceSmartPlaylist = args.contains("--era-demo")
        if args.contains("--era-smart-playlist") {
            _sectionRaw = AppStorage(wrappedValue: LibrarySection.playlists.rawValue, AppSettings.librarySectionKey)
            _demoSectionOnly = State(initialValue: true)
            _showSmartPlaylist = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty { emptyState } else { content }
            }
            .navigationTitle(selecting ? selectionTitle : String(localized: "Library"))
            .toolbar {
                if selecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(LocalizedStringKey(selection.coversAll(of: sortedSongs.map(\.id)) ? "Deselect All" : "Select All")) {
                            if selection.coversAll(of: sortedSongs.map(\.id)) { selection.clear() } else { selection.selectAll(sortedSongs.map(\.id)) }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { endSelecting() }.fontWeight(.semibold)
                    }
                    SongSelectionToolbar(chosen: selectedSongs, store: store, playlistPicker: playlistPicker, showTags: $showBulkTags, confirmDelete: $confirmBulkDelete)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { showImporter = true } label: { Label("Files", systemImage: "doc.on.doc") }
                            Button { showFolderImporter = true } label: { Label("Folder", systemImage: "folder") }
                            Button { importer.showMassImport = true } label: { Label("Files with Review", systemImage: "checklist") }
                        } label: { Label("Import Music", systemImage: "square.and.arrow.down") }
                        .accessibilityLabel("Import Music")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Settings")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort", selection: Binding(get: { sort }, set: { sortRaw = $0.rawValue })) {
                                ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                            }
                            if [.songs, .albums, .artists].contains(selectedSection) && !songs.isEmpty {
                                filterMenuItems
                            }
                            if selectedSection == .songs && !songs.isEmpty {
                                Divider()
                                Button { selecting = true } label: { Label("Select Songs", systemImage: "checkmark.circle") }
                            }
                        } label: {
                            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("Sort")
                    }
                }
            }
            .navigationBarTitleDisplayMode(selecting ? .inline : .automatic)
            .toolbar(selecting ? .hidden : .automatic, for: .tabBar)
            .onChange(of: songs.count) { _, _ in selection.prune(to: Set(songs.map(\.id))) }
            .onReceive(NotificationCenter.default.publisher(for: .eraImportMusic)) { _ in showImporter = true }
            .onReceive(NotificationCenter.default.publisher(for: .eraNewPlaylist)) { _ in
                sectionRaw = LibrarySection.playlists.rawValue
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    showNewPlaylist = true
                }
            }
            .sheet(isPresented: $showBulkTags) { BulkTagSheet(songs: selectedSongs) }
            .confirmationDialog("Delete Songs?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
                Button("Delete \(selection.count) Songs", role: .destructive) {
                    store.deleteSongs(selectedSongs)
                    endSelecting()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the songs with all their versions and local audio files.")
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $demoSongSheet) {
                if let song = songs.max(by: { $0.versions.count < $1.versions.count }) {
                    SongDetailView(song: song, showNowPlaying: $showNowPlaying)
                }
            }
            .sheet(isPresented: $demoPlaylistSheet) {
                if let playlist = playlists.first {
                    NavigationStack {
                        PlaylistDetailView(playlist: playlist, showNowPlaying: $showNowPlaying)
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker(contentTypes: ImportManager.importableTypes) { urls in
                    showImporter = false
                    guard !urls.isEmpty else { noFilesNotice(); return }
                    Task { await importer.importFiles(urls, into: store) }
                } onCancel: { showImporter = false }
            }
            .sheet(isPresented: $showFolderImporter) {
                DocumentPicker(contentTypes: [.folder], asCopy: false) { urls in
                    showFolderImporter = false
                    guard !urls.isEmpty else { noFilesNotice(); return }
                    Task { await importer.stage(urls, existing: songs) }
                } onCancel: { showFolderImporter = false }
            }
            .sheet(isPresented: $importer.showMassImport) {
                MassImportView()
            }
            .sheet(isPresented: $showSmartPlaylist) {
                SmartPlaylistView()
            }
.confirmationDialog("Delete Song?", isPresented: Binding(get: { songToDelete != nil }, set: { if !$0 { songToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete Song", role: .destructive) { if let song = songToDelete { store.deleteSong(song) }; songToDelete = nil }
                Button("Cancel", role: .cancel) { songToDelete = nil }
            } message: { if let song = songToDelete { Text("This removes \(song.versions.count) version(s) and their local audio files.") } }
            .confirmationDialog("Delete Playlist?", isPresented: Binding(get: { playlistToDelete != nil }, set: { if !$0 { playlistToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete Playlist", role: .destructive) { if let playlist = playlistToDelete { store.deletePlaylist(playlist) }; playlistToDelete = nil }
                Button("Cancel", role: .cancel) { playlistToDelete = nil }
            } message: { Text("Songs stay in your library.") }
            .alert("Era", isPresented: Binding(get: { importer.message != nil }, set: { if !$0 { importer.message = nil } })) {
                Button("OK") { importer.message = nil }
            } message: {
                Text(importer.message ?? "")
            }
            .overlay(alignment: .bottom) {
                if importer.isImporting {
                    Label("Importing…", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .eraGlassCapsule()
                        .padding(.bottom, 70)
                }
            }
        }
    }

    private func noFilesNotice() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            importer.message = String(localized: "No files were imported. Are the songs stored locally on this iPhone, not only in iCloud?")
        }
    }

    /// Der Filter wird gemerkt (AppStorage), damit er nach einem Neustart noch aktiv ist.
    private var filter: LibraryFilter {
        get { LibraryFilter.decode(filterRaw) }
        nonmutating set { filterRaw = newValue.encoded }
    }

    private var selectedSongs: [Song] { songs.filter { selection.contains($0.id) } }
    private var selectionTitle: String {
        selection.isEmpty ? String(localized: "Select Songs") : String(format: String(localized: "%lld Selected"), selection.count)
    }

    private func endSelecting() {
        selecting = false
        selection.clear()
    }

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }
    private var songsByID: [UUID: Song] { Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }

    private var selectedSection: LibrarySection { LibrarySection(rawValue: sectionRaw) ?? .songs }

    @ViewBuilder private var content: some View {
        if demoSectionOnly {
            List { playlistsSection }.listStyle(.plain)
        } else {
            VStack(spacing: 0) {
                Picker("Library View", selection: $sectionRaw) {
                    ForEach([LibrarySection.songs, .albums, .artists, .playlists]) { Text(LocalizedStringKey($0.rawValue)).tag($0.rawValue) }
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
                switch selectedSection {
                case .songs: List { songsSection }.listStyle(.plain)
                case .albums: albumList
                case .artists: artistList
                case .playlists: List { playlistsSection }.listStyle(.plain)
                case .versions: List { versionsSection }.listStyle(.plain)
                }
            }
        }
    }

    private var artistList: some View {
        let byID = songsByID
        let groups = LibraryGrouping.groups(of: filteredSongs.map { ($0.id, $0.artist) })
        return List {
            filterSummary
            ForEach(groups) { group in
                let members = group.ids.compactMap { byID[$0] }
                let name = group.name.isEmpty ? String(localized: "Unknown Artist") : group.name
                NavigationLink { CollectionDetailView(title: name, songs: members, kind: .artist, showNowPlaying: $showNowPlaying) } label: {
                    HStack(spacing: 14) {
                        Artwork(song: members.first, radius: 34).scaledSquare(64).clipShape(Circle())
                        VStack(alignment: .leading) { Text(name); Text("\(members.count) tracks").font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
        }.listStyle(.plain)
    }

    private var albumList: some View {
        let byID = songsByID
        let groups = LibraryGrouping.groups(of: filteredSongs.map { ($0.id, $0.album) })
        return List {
            filterSummary
            ForEach(groups) { group in
                let members = group.ids.compactMap { byID[$0] }
                let name = group.name.isEmpty ? String(localized: "Unknown Album") : group.name
                NavigationLink { CollectionDetailView(title: name, songs: members, kind: .album, showNowPlaying: $showNowPlaying) } label: {
                    HStack(spacing: 14) {
                        Artwork(song: members.first, radius: 8).scaledSquare(64)
                        VStack(alignment: .leading) { Text(name); Text(members.first?.displayArtist ?? "").font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
        }.listStyle(.plain)
    }

    /// Songs after the (remembered) library filter; shared by songs, albums and artists.
    private var filteredSongs: [Song] {
        guard filter.isActive else { return songs }
        let allowed = Set(filter.ids(in: songs.map(\.searchable)))
        return songs.filter { allowed.contains($0.id) }
    }

    private var sortedSongs: [Song] {
        let base = filteredSongs
        guard sort != .recent else { return base }
        let byID = songsByID
        return sort.ordered(base.map(\.sortRow)).compactMap { byID[$0] }
    }

    @ViewBuilder private var filterMenuItems: some View {
        Section("Filter") {
            Toggle(isOn: Binding(get: { filter.favoritesOnly }, set: { filter.favoritesOnly = $0 })) { Label("Favorites", systemImage: "heart") }
            let statuses = allTags.filter { $0.isStatus && !$0.songs.isEmpty }
            if !statuses.isEmpty {
                Menu {
                    ForEach(statuses) { tag in
                        Toggle(tag.name, isOn: Binding(get: { filter.statuses.contains(tag.name) }, set: { _ in filter.toggle(status: tag.name) }))
                    }
                } label: { Label("Status", systemImage: "circle.dashed") }
            }
            let personal = allTags.filter { !$0.isStatus && !$0.songs.isEmpty }
            if !personal.isEmpty {
                Menu {
                    ForEach(personal) { tag in
                        Toggle(tag.name, isOn: Binding(get: { filter.tags.contains(tag.name) }, set: { _ in filter.toggle(tag: tag.name) }))
                    }
                } label: { Label("Tags", systemImage: "tag") }
            }
            Menu {
                ForEach(LibraryFilter.Attribute.allCases, id: \.self) { attribute in
                    Toggle(attribute.title, isOn: Binding(get: { filter.attributes.contains(attribute) }, set: { _ in filter.toggle(attribute) }))
                }
            } label: { Label("Show Only", systemImage: "line.3.horizontal.decrease") }
            if filter.isActive {
                Button(role: .destructive) { filter = LibraryFilter() } label: { Label("Clear Filters", systemImage: "xmark.circle") }
            }
        }
    }

    @ViewBuilder private var filterSummary: some View {
        if filter.isActive {
            HStack {
                Label("\(sortedSongs.count) of \(songs.count) songs", systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { withAnimation { filter = LibraryFilter() } }
                    .font(.footnote.weight(.semibold)).buttonStyle(.borderless)
            }
            if sortedSongs.isEmpty {
                Text("No song matches the active filters.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var songsSection: some View {
        let ordered = sortedSongs
        if !selecting, let groups = AlphaSections.sections(orderedRows: ordered.map(\.sortRow), sort: sort) {
            // Lange Listen nach Titel/Artist: Buchstaben-Abschnitte statt einer endlosen Liste.
            let byID = songsByID
            Section {
                filterSummary
                playAllButtons
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.ids.compactMap { byID[$0] }) { songRow($0) }
                } header: {
                    Text(verbatim: group.letter)
                }
            }
            if !filter.isActive { Section { } footer: { songsFooter } }
        } else {
            Section {
                filterSummary
                if !selecting && !ordered.isEmpty {
                    playAllButtons
                }
                ForEach(ordered) { song in
                    if selecting {
                        selectableRow(song)
                    } else {
                        songRow(song)
                    }
                }
            } footer: {
                if !selecting && !filter.isActive && !songs.isEmpty { songsFooter }
            }
        }
    }

    private var songsFooter: some View {
        (Text("\(songs.count) songs") + Text(verbatim: " · \(TimeFormatting.spoken(songs.reduce(0) { $0 + $1.duration }))"))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private var playAllButtons: some View {
        Button {
            let versions = sortedSongs.compactMap(\.primaryVersion)
            if let first = versions.first { player.play(first, from: versions) }
        } label: {
            Label("Play All (\(sortedSongs.count))", systemImage: "play.fill")
        }
        Button {
            player.playShuffled(sortedSongs.compactMap(\.primaryVersion))
        } label: {
            Label("Shuffle", systemImage: "shuffle")
        }
    }

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: 8) {
            Button {
                if let version = song.primaryVersion { player.play(version, from: sortedSongs.compactMap(\.primaryVersion)); showNowPlaying = true }
            } label: { SongRow(song: song, version: nil, isCurrent: player.current?.song?.id == song.id) }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink { SongDetailView(song: song, showNowPlaying: $showNowPlaying) } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Song Details")
        }
        .swipeActions(edge: .leading) {
            Button { song.isFavorite.toggle(); store.save() } label: {
                Label("Favorite", systemImage: song.isFavorite ? "heart.slash" : "heart.fill")
            }.tint(.pink)
        }
        .swipeActions {
            Button(role: .destructive) { songToDelete = song } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu { SongContextMenu(song: song, showNowPlaying: $showNowPlaying) }
    }

    private func selectableRow(_ song: Song) -> some View {
        SelectableSongRow(song: song, isSelected: selection.contains(song.id)) { selection.toggle(song.id) }
    }

    private var playlistsSection: some View {
        Section {
            ForEach(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist, showNowPlaying: $showNowPlaying)
                } label: {
                    HStack(spacing: 14) {
                        PlaylistMosaic(playlist: playlist)
                            .scaledSquare(64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name).font(.body)
                            Text("\(playlist.entries.count) tracks")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .swipeActions {
                    Button(role: .destructive) { playlistToDelete = playlist } label: { Label("Delete", systemImage: "trash") }
                }
                .contextMenu {
                    Button("Delete Playlist", systemImage: "trash", role: .destructive) { playlistToDelete = playlist }
                }
            }
            Button { showNewPlaylist = true } label: { Label("New Playlist", systemImage: "plus") }
            if IntelligenceService.isAvailable || demoForceSmartPlaylist {
                Button { showSmartPlaylist = true } label: {
                    Label("Smart Playlist", systemImage: "sparkles")
                }
            }
        }
        .alert("New Playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Erstellen") {
                store.createPlaylist(named: newPlaylistName)
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        }
    }

    private var versionsSection: some View {
        Section {
            ForEach(songs) { song in
                ForEach(song.sortedVersions) { version in
                    HStack(spacing: 12) {
                        Artwork(song: song, version: version, radius: 7).scaledSquare(40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.body).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(version.name)
                                if let year = version.year { Text(verbatim: "· \(year)") }
                            }
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                        Text(version.durationText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { player.play(version, from: [version]) }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your Music. Your iPhone.", systemImage: "waveform.circle.fill")
        } description: {
            Text("Import MP3, M4A, WAV, FLAC, and more from the Files app.")
        } actions: {
            Button { showImporter = true } label: { Label("Import Songs", systemImage: "square.and.arrow.down") }
                .eraProminentButton()
        }
    }
}

// Schlichtes Listen-Ziel fuer automatische Sammlungen: Tippen spielt ab, "..." oeffnet die Details.
struct SongListView: View {
    let title: String
    let songs: [Song]
    @Binding var showNowPlaying: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore
    @EnvironmentObject private var playlistPicker: PlaylistPickerCoordinator
    @State private var selecting = false
    @State private var selection = BulkSelection()
    @State private var showBulkTags = false
    @State private var confirmBulkDelete = false

    private var selectedSongs: [Song] { songs.filter { selection.contains($0.id) } }
    private var selectionTitle: String {
        selection.isEmpty ? String(localized: "Select Songs") : String(format: String(localized: "%lld Selected"), selection.count)
    }

    private func endSelecting() {
        selecting = false
        selection.clear()
    }

    var body: some View {
        List {
            if songs.count > 1 && !selecting {
                Section {
                    Button {
                        let versions = songs.compactMap(\.primaryVersion)
                        if let first = versions.first { player.play(first, from: versions) }
                    } label: { Label("Play All", systemImage: "play.fill") }
                    Button {
                        player.playShuffled(songs.compactMap(\.primaryVersion))
                    } label: { Label("Shuffle", systemImage: "shuffle") }
                }
            }
            Section {
                ForEach(songs) { song in
                    if selecting {
                        SelectableSongRow(song: song, isSelected: selection.contains(song.id)) { selection.toggle(song.id) }
                    } else {
                        HStack(spacing: 8) {
                            Button {
                                if let v = song.primaryVersion { player.play(v, from: songs.compactMap(\.primaryVersion)); showNowPlaying = true }
                            } label: { SongRow(song: song, version: nil, isCurrent: player.current?.song?.id == song.id) }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            NavigationLink { SongDetailView(song: song, showNowPlaying: $showNowPlaying) } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityLabel("Song Details")
                        }
                        .swipeActions(edge: .leading) {
                            Button { song.isFavorite.toggle(); store.save() } label: {
                                Label("Favorite", systemImage: song.isFavorite ? "heart.slash" : "heart.fill")
                            }.tint(.pink)
                        }
                        .contextMenu { SongContextMenu(song: song, showNowPlaying: $showNowPlaying) }
                    }
                }
            }
        }
        .navigationTitle(selecting ? selectionTitle : title)
        .toolbar {
            if selecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button(LocalizedStringKey(selection.coversAll(of: songs.map(\.id)) ? "Deselect All" : "Select All")) {
                        if selection.coversAll(of: songs.map(\.id)) { selection.clear() } else { selection.selectAll(songs.map(\.id)) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { endSelecting() }.fontWeight(.semibold)
                }
                SongSelectionToolbar(chosen: selectedSongs, store: store, playlistPicker: playlistPicker, showTags: $showBulkTags, confirmDelete: $confirmBulkDelete)
            } else if songs.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { selecting = true } label: { Label("Select Songs", systemImage: "checkmark.circle") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More")
                }
            }
        }
        .toolbar(selecting ? .hidden : .automatic, for: .tabBar)
        .sheet(isPresented: $showBulkTags) { BulkTagSheet(songs: selectedSongs) }
        .confirmationDialog("Delete Songs?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button("Delete \(selection.count) Songs", role: .destructive) {
                store.deleteSongs(selectedSongs)
                endSelecting()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the songs with all their versions and local audio files.")
        }
    }
}

enum CollectionKind { case artist, album }

struct CollectionDetailView: View {
    let title: String
    let songs: [Song]
    let kind: CollectionKind
    @Binding var showNowPlaying: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore
    @EnvironmentObject private var playlistPicker: PlaylistPickerCoordinator
    @State private var selecting = false
    @State private var selection = BulkSelection()
    @State private var showBulkTags = false
    @State private var confirmBulkDelete = false

    private var selectedSongs: [Song] { songs.filter { selection.contains($0.id) } }

    private var totalDurationText: String {
        let count = String(localized: "\(songs.count) tracks")
        return count + " · " + TimeFormatting.spoken(songs.reduce(0) { $0 + $1.duration })
    }

    private func endSelecting() {
        selecting = false
        selection.clear()
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                Divider().padding(.horizontal, 18)
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    row(index: index, song: song)
                    Divider().padding(.leading, 54)
                }
            }
        }
        .navigationTitle(selecting ? selectionTitle : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button(LocalizedStringKey(selection.coversAll(of: songs.map(\.id)) ? "Deselect All" : "Select All")) {
                        if selection.coversAll(of: songs.map(\.id)) { selection.clear() } else { selection.selectAll(songs.map(\.id)) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { endSelecting() }.fontWeight(.semibold)
                }
                SongSelectionToolbar(chosen: selectedSongs, store: store, playlistPicker: playlistPicker, showTags: $showBulkTags, confirmDelete: $confirmBulkDelete)
            } else if songs.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { selecting = true } label: { Label("Select Songs", systemImage: "checkmark.circle") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More")
                }
            }
        }
        .toolbar(selecting ? .hidden : .automatic, for: .tabBar)
        .sheet(isPresented: $showBulkTags) { BulkTagSheet(songs: selectedSongs) }
        .confirmationDialog("Delete Songs?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button("Delete \(selection.count) Songs", role: .destructive) {
                store.deleteSongs(selectedSongs)
                endSelecting()
                // The list holds the deleted models; leave instead of showing stale rows.
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the songs with all their versions and local audio files.")
        }
    }

    private var selectionTitle: String {
        selection.isEmpty ? String(localized: "Select Songs") : String(format: String(localized: "%lld Selected"), selection.count)
    }

    private var header: some View {
        VStack(spacing: 14) {
            if let song = songs.first {
                Artwork(song: song, radius: kind == .artist ? 120 : 14)
                    .scaledSquare(250)
                    .clipShape(kind == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
                    .shadow(color: .black.opacity(0.25), radius: 22, y: 12)
            }
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            if kind == .album {
                Text(songs.first?.displayArtist ?? "").font(.title3).foregroundStyle(.tint)
                Text([songs.first?.era, songs.first?.year.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(totalDurationText).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                Button { player.playShuffled(songs.compactMap(\.primaryVersion)) } label: {
                    Image(systemName: "shuffle").font(.title2).frame(width: 52, height: 52).background(.thinMaterial, in: .circle)
                }
                .accessibilityLabel("Shuffle")
                Button {
                    let versions = songs.compactMap(\.primaryVersion)
                    if let first = versions.first { player.play(first, from: versions); showNowPlaying = true }
                } label: {
                    Label("Play", systemImage: "play.fill").font(.headline).padding(.horizontal, 25).frame(height: 52)
                        .background(Color.accentColor, in: .capsule).foregroundStyle(.white)
                }
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 20)
    }

    @ViewBuilder private func row(index: Int, song: Song) -> some View {
        if selecting {
            SelectableSongRow(song: song, isSelected: selection.contains(song.id)) { selection.toggle(song.id) }
                .padding(.horizontal, 18).padding(.vertical, 6)
        } else {
            let isCurrent = player.current?.song?.id == song.id
            HStack(spacing: 12) {
                Group {
                    if isCurrent {
                        Image(systemName: "waveform").foregroundStyle(.tint)
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                    } else {
                        Text("\(index + 1)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).lineLimit(1).foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    Text(song.displayArtist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if song.isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink) }
                Text(song.durationText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Menu { SongContextMenu(song: song, showNowPlaying: $showNowPlaying) } label: {
                    Image(systemName: "ellipsis").frame(width: 40, height: 40)
                }
                .accessibilityLabel("More")
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { if let v = song.primaryVersion { player.play(v, from: songs.compactMap(\.primaryVersion)) } }
            .contextMenu { SongContextMenu(song: song, showNowPlaying: $showNowPlaying) }
        }
    }
}

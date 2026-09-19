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

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "Recently Added", title = "Title", artist = "Artist"
    var id: String { rawValue }
}

struct LibraryView: View {
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var store: EraStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var importer: ImportManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.dateAdded, order: .reverse) private var songs: [Song]
    @Query private var playlists: [Playlist]

    @AppStorage(AppSettings.librarySectionKey) private var sectionRaw = LibrarySection.songs.rawValue
    @State private var sort: LibrarySort = .recent
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
            .navigationTitle("Library")
            .toolbar {
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
                        Picker("Sort", selection: $sort) {
                            ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")
                }
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
            importer.message = "No files were imported. Are the songs stored locally on this iPhone, not only in iCloud?"
        }
    }

    private var selectedSection: LibrarySection { LibrarySection(rawValue: sectionRaw) ?? .songs }

    @ViewBuilder private var content: some View {
        if demoSectionOnly {
            List { playlistsSection }.listStyle(.plain)
        } else {
            VStack(spacing: 0) {
                Picker("Library View", selection: $sectionRaw) {
                    ForEach([LibrarySection.songs, .albums, .artists, .playlists]) { Text($0.rawValue).tag($0.rawValue) }
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

    private func libraryLink(_ title: String, icon: String, destination: AnyView) -> some View {
        NavigationLink { destination } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 30)
                Text(title).font(.title3)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(.tertiary)
            }.padding(.horizontal, 18).frame(height: 52)
        }.buttonStyle(.plain)
    }

    private var playlistList: some View { List { playlistsSection }.listStyle(.plain).navigationTitle("Playlists") }
    private var songList: some View { List { songsSection }.listStyle(.plain).navigationTitle("Title") }
    private var versionList: some View { List { versionsSection }.listStyle(.plain).navigationTitle("Versions") }
    private var artistList: some View {
        let grouped = Dictionary(grouping: songs) { $0.displayArtist }
        return List(grouped.keys.sorted(), id: \.self) { name in
            NavigationLink { CollectionDetailView(title: name, songs: grouped[name] ?? [], kind: .artist, showNowPlaying: $showNowPlaying) } label: {
                HStack(spacing: 14) {
                    Artwork(song: grouped[name]?.first, radius: 34).frame(width: 64, height: 64).clipShape(Circle())
                    VStack(alignment: .leading) { Text(name); Text("\(grouped[name]?.count ?? 0) tracks").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
        }.listStyle(.plain).navigationTitle("Artists")
    }
    private var albumList: some View {
        let grouped = Dictionary(grouping: songs) { $0.album.isEmpty ? "Unknown Album" : $0.album }
        return List(grouped.keys.sorted(), id: \.self) { name in
            NavigationLink { CollectionDetailView(title: name, songs: grouped[name] ?? [], kind: .album, showNowPlaying: $showNowPlaying) } label: {
                HStack(spacing: 14) {
                    Artwork(song: grouped[name]?.first, radius: 8).frame(width: 64, height: 64)
                    VStack(alignment: .leading) { Text(name); Text(grouped[name]?.first?.displayArtist ?? "").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
        }.listStyle(.plain).navigationTitle("Albums")
    }

    private var sortedSongs: [Song] {
        switch sort {
        case .recent: return songs
        case .title: return songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: return songs.sorted {
            let a = $0.displayArtist.localizedStandardCompare($1.displayArtist)
            return a == .orderedSame ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : a == .orderedAscending
        }
        }
    }

    private var songsSection: some View {
        Section {
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
            ForEach(sortedSongs) { song in
                HStack(spacing: 8) {
                    Button {
                        if let version = song.primaryVersion { player.play(version, from: sortedSongs.compactMap(\.primaryVersion)); showNowPlaying = true }
                    } label: { SongRow(song: song, version: nil, isCurrent: player.current?.song?.id == song.id) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NavigationLink { SongDetailView(song: song, showNowPlaying: $showNowPlaying) } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }
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
        }
    }

    private var artistsSection: some View {
        let grouped = Dictionary(grouping: songs) { $0.displayArtist }
        let names = grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return Section {
            ForEach(names, id: \.self) { name in
                NavigationLink {
                    CollectionDetailView(title: name, songs: grouped[name] ?? [], kind: .artist, showNowPlaying: $showNowPlaying)
                } label: {
                    Label("\(name) (\(grouped[name]?.count ?? 0))", systemImage: "person.fill")
                }
            }
        }
    }

    private var albumsSection: some View {
        let grouped = Dictionary(grouping: songs) { $0.album.isEmpty ? "Unknown Album" : $0.album }
        let names = grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return Section {
            ForEach(names, id: \.self) { name in
                NavigationLink {
                    CollectionDetailView(title: name, songs: grouped[name] ?? [], kind: .album, showNowPlaying: $showNowPlaying)
                } label: {
                    Label("\(name) (\(grouped[name]?.count ?? 0))", systemImage: "square.stack")
                }
            }
        }
    }

    private var playlistsSection: some View {
        Section {
            ForEach(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist, showNowPlaying: $showNowPlaying)
                } label: {
                    HStack(spacing: 14) {
                        PlaylistMosaic(playlist: playlist)
                            .frame(width: 64, height: 64)
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
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.insertPlaylist(Playlist(name: name)) }
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
                        Artwork(song: song, version: version, radius: 7).frame(width: 40, height: 40)
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

// Schlichtes Listen-Ziel fuer Artists/Alben
struct SongListView: View {
    let title: String
    let songs: [Song]
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore

    var body: some View {
        List {
            if songs.count > 1 {
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
                    NavigationLink {
                        SongDetailView(song: song, showNowPlaying: $showNowPlaying)
                    } label: {
                        SongRow(song: song, version: nil, isCurrent: player.current?.song?.id == song.id)
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
        .navigationTitle(title)
    }
}

enum CollectionKind { case artist, album }

struct CollectionDetailView: View {
    let title: String
    let songs: [Song]
    let kind: CollectionKind
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                VStack(spacing: 14) {
                    if let song = songs.first {
                        Artwork(song: song, radius: kind == .artist ? 120 : 14)
                            .frame(width: 250, height: 250)
                            .clipShape(kind == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
                            .shadow(color: .black.opacity(0.25), radius: 22, y: 12)
                    }
                    Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    if kind == .album {
                        Text(songs.first?.displayArtist ?? "").font(.title3).foregroundStyle(.tint)
                        Text([songs.first?.era, songs.first?.year.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 18) {
                        Button { player.playShuffled(songs.compactMap(\.primaryVersion)) } label: {
                            Image(systemName: "shuffle").font(.title2).frame(width: 52, height: 52).background(.thinMaterial, in: .circle)
                        }
                        Button {
                            let versions = songs.compactMap(\.primaryVersion)
                            if let first = versions.first { player.play(first, from: versions); showNowPlaying = true }
                        } label: {
                            Label("Wiedergeben", systemImage: "play.fill").font(.headline).padding(.horizontal, 25).frame(height: 52)
                                .background(Color.accentColor, in: .capsule).foregroundStyle(.white)
                        }
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 18).padding(.vertical, 20)
                Divider().padding(.horizontal, 18)
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.subheadline).foregroundStyle(.secondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).lineLimit(1)
                            Text(song.displayArtist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Menu { Button("Up Next") { if let v = song.primaryVersion { player.playNext(v) } } } label: { Image(systemName: "ellipsis").frame(width: 40, height: 40) }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .contentShape(Rectangle()).onTapGesture { if let v = song.primaryVersion { player.play(v, from: songs.compactMap(\.primaryVersion)) } }
                    Divider().padding(.leading, 54)
                }
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

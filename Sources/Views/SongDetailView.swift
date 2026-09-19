import SwiftUI
import SwiftData

// Song-Detail: primaere Version gross, alle Versionen darunter, Verknuepfen-Flow (Spec 4).
struct SongDetailView: View {
    let song: Song
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var store: EraStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var importer: ImportManager
    @State private var showVersionDrawer = false
    @State private var showMetadataEditor = false
    @State private var versionToRename: SongVersion?
    @State private var shareItem: ShareItem?
    @State private var menuVersion: SongVersion?

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Artwork(song: song, radius: 14).frame(width: 88, height: 88)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title).font(.title3.bold()).lineLimit(2)
                        Text(song.displayArtist).foregroundStyle(.secondary)
                        if !song.era.isEmpty { Text(song.era).font(.caption).foregroundStyle(.secondary) }
                        HStack(spacing: 6) {
                            ForEach(song.statusTags) { tag in StatusChip(text: tag.name) }
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            Section {
                HStack(spacing: 12) {
                    Button { if let v = song.primaryVersion { player.play(v, from: [v]); showNowPlaying = true } } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity) }.eraProminentButton()
                    Button { song.isFavorite.toggle(); store.save() } label: { Image(systemName: song.isFavorite ? "heart.fill" : "heart").frame(width: 44, height: 44) }
                        .buttonStyle(.bordered).accessibilityLabel(song.isFavorite ? "Remove Favorite" : "Add to Favorites")
                }
            }

            Section("Manage") {
                Button { showMetadataEditor = true } label: { Label("Edit Metadata", systemImage: "pencil") }
                Button { showVersionDrawer = true } label: { Label("Add Version", systemImage: "plus.rectangle.on.rectangle") }
            }

            Section("Versions (\(song.versions.count))") {
                ForEach(song.sortedVersions) { version in
                    VersionRow(song: song, version: version, isCurrent: player.current?.id == version.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.play(version, from: [version])
                        }
                        .contextMenu { versionMenu(version) }
                        .overlay(alignment: .trailing) {
                            Menu { versionMenu(version) } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        }
                }
            }

            if !song.personalTags.isEmpty {
                Section("Tags") {
                    FlowTags(tags: song.personalTags)
                }
            }
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showVersionDrawer) { VersionDrawer(song: song) }
        .sheet(isPresented: $showMetadataEditor) { MetadataEditView(song: song) }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
    }

    @ViewBuilder
    private func shareButton(_ version: SongVersion) -> some View {
        let url = LibraryFiles.url(for: version)
        if FileManager.default.fileExists(atPath: url.path) {
            Button { shareItem = ShareItem(url: url) } label: {
                Label("Share Version", systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private func versionMenu(_ version: SongVersion) -> some View {
        Button {
            song.primaryVersionID = version.id
            store.save()
        } label: { Label("Make Primary Version", systemImage: "star") }
        shareButton(version)
        Button {
            versionToRename = version
        } label: { Label("Umbenennen", systemImage: "pencil") }
        if song.versions.count > 1 {
            Button {
                separate(version)
            } label: { Label("Detach from Song", systemImage: "scissors") }
            Divider()
            Button(role: .destructive) {
                deleteVersion(version)
            } label: { Label("Delete Version", systemImage: "trash") }
        }
    }

    private func separate(_ version: SongVersion) {
        // Trennen: Version wird wieder eigener Song (Spec 4), Datei/Metadaten bleiben
        song.versions.removeAll { $0.id == version.id }
        let newSong = Song(title: version.displayTitle, artist: version.displayArtist, album: version.displayAlbum, era: song.era, year: version.year)
        newSong.versions.append(version)
        version.song = newSong
        newSong.primaryVersionID = version.id
        newSong.tags = song.tags
        store.insertSong(newSong)
        if song.primaryVersionID == version.id { song.primaryVersionID = song.sortedVersions.first?.id }
        store.save()
    }

    private func deleteVersion(_ version: SongVersion) {
        VersionFiles.delete(version: version)
        song.versions.removeAll { $0.id == version.id }
        if song.primaryVersionID == version.id { song.primaryVersionID = song.sortedVersions.first?.id }
        store.context.delete(version)
        store.save()
    }
}

struct VersionRow: View {
    let song: Song
    let version: SongVersion
    var isCurrent: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "opticaldisc")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(version.name).font(.body.weight(.medium))
                    if song.primaryVersion?.id == version.id {
                        Text("Primary")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: .capsule)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                HStack(spacing: 4) {
                    if version.displayTitle != song.title { Text(version.displayTitle) }
                    if let year = version.year { Text(verbatim: String(year)) }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "waveform").foregroundStyle(.tint).symbolEffect(.variableColor.iterative, isActive: true)
            } else {
                Text(version.durationText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

struct StatusChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: .capsule)
            .foregroundStyle(.secondary)
    }
}

struct FlowTags: View {
    let tags: [Tag]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags) { StatusChip(text: $0.name) }
            }
        }
    }
}

// Kontextmenue am Song (Drei-Punkte-Logik, Spec 4): Version aufklappbar,
// oben "+ Add", darunter alle Versionen des Songs.
struct SongContextMenu: View {
    let song: Song
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore
    @State private var showDrawer = false
    @State private var shareItem: ShareItem?
    @State private var menuVersion: SongVersion?

    var body: some View {
        Group {
            Button {
                if let v = song.primaryVersion { player.play(v, from: [v]) }
            } label: { Label("Play", systemImage: "play.fill") }
            Button {
                if let v = song.primaryVersion { player.playNext(v) }
            } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button {
                if let v = song.primaryVersion { player.playLater(v) }
            } label: { Label("Add to End", systemImage: "text.line.last.and.arrowtriangle.forward") }
            Menu {
                Button { showDrawer = true } label: { Label("Add", systemImage: "plus") }
                Divider()
                ForEach(song.sortedVersions) { version in
                    Button {
                        player.play(version, from: [version])
                    } label: {
                        Label(versionLabel(version), systemImage: version.id == song.primaryVersion?.id ? "star.fill" : "opticaldisc")
                    }
                }
            } label: { Label("Version", systemImage: "square.stack") }
            Divider()
            Button { song.isFavorite.toggle(); store.save() } label: {
                Label(song.isFavorite ? "Remove Favorite" : "Favorite", systemImage: song.isFavorite ? "heart.slash" : "heart")
            }
            if let v = song.primaryVersion {
                let url = LibraryFiles.url(for: v)
                if FileManager.default.fileExists(atPath: url.path) {
                    Button { shareItem = ShareItem(url: url) } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showDrawer) { VersionDrawer(song: song) }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
    }

    private func versionLabel(_ version: SongVersion) -> String {
        if let year = version.year { return "\(version.name) (\(year))" }
        return version.name
    }
}

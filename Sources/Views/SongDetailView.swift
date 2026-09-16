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
                Button {
                    if let v = song.primaryVersion { player.play(v, from: song.sortedVersions) }
                } label: { Label("Abspielen", systemImage: "play.fill") }
                Button {
                    song.isFavorite.toggle(); store.save()
                } label: {
                    Label(song.isFavorite ? "Favorit entfernen" : "Zu Favoriten", systemImage: song.isFavorite ? "heart.slash" : "heart.fill")
                }
                Button { showMetadataEditor = true } label: { Label("Metadaten bearbeiten", systemImage: "pencil") }
                Button { showVersionDrawer = true } label: { Label("Version hinzufügen", systemImage: "plus.rectangle.on.rectangle") }
            }

            Section("Versionen (\(song.versions.count))") {
                ForEach(song.sortedVersions) { version in
                    VersionRow(song: song, version: version, isCurrent: player.current?.id == version.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.play(version, from: song.sortedVersions)
                        }
                        .contextMenu { versionMenu(version) }
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
                Label("Version teilen", systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private func versionMenu(_ version: SongVersion) -> some View {
        Button {
            song.primaryVersionID = version.id
            store.save()
        } label: { Label("Als primäre Version", systemImage: "star") }
        shareButton(version)
        Button {
            versionToRename = version
        } label: { Label("Umbenennen", systemImage: "pencil") }
        if song.versions.count > 1 {
            Button {
                separate(version)
            } label: { Label("Vom Song trennen", systemImage: "scissors") }
            Divider()
            Button(role: .destructive) {
                deleteVersion(version)
            } label: { Label("Version löschen", systemImage: "trash") }
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
                        Text("Primär")
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
// oben "+ Hinzufuegen", darunter alle Versionen des Songs.
struct SongContextMenu: View {
    let song: Song
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore
    @State private var showDrawer = false
    @State private var shareItem: ShareItem?

    var body: some View {
        Group {
            Button {
                if let v = song.primaryVersion { player.play(v, from: song.sortedVersions) }
            } label: { Label("Abspielen", systemImage: "play.fill") }
            Button {
                if let v = song.primaryVersion { player.playNext(v) }
            } label: { Label("Als Nächstes abspielen", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button {
                if let v = song.primaryVersion { player.playLater(v) }
            } label: { Label("Zum Schluss hinzufügen", systemImage: "text.line.last.and.arrowtriangle.forward") }
            Menu {
                Button { showDrawer = true } label: { Label("Hinzufügen", systemImage: "plus") }
                Divider()
                ForEach(song.sortedVersions) { version in
                    Button {
                        player.play(version, from: song.sortedVersions)
                    } label: {
                        Label(versionLabel(version), systemImage: version.id == song.primaryVersion?.id ? "star.fill" : "opticaldisc")
                    }
                }
            } label: { Label("Version", systemImage: "square.stack") }
            Divider()
            Button { song.isFavorite.toggle(); store.save() } label: {
                Label(song.isFavorite ? "Favorit entfernen" : "Favorit", systemImage: song.isFavorite ? "heart.slash" : "heart")
            }
            if let v = song.primaryVersion {
                let url = LibraryFiles.url(for: v)
                if FileManager.default.fileExists(atPath: url.path) {
                    Button { shareItem = ShareItem(url: url) } label: {
                        Label("Teilen", systemImage: "square.and.arrow.up")
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

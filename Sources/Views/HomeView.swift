import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore
    @Query(sort: \Song.dateAdded, order: .reverse) private var songs: [Song]
    @Query private var packs: [Pack]
    @EnvironmentObject private var importer: ImportManager
    @State private var showStats = ProcessInfo.processInfo.arguments.contains("--era-stats")
    @State private var showImporter = false
    @State private var showBackupTools = false
    @AppStorage(AppSettings.lastBackupKey) private var lastBackup = 0.0
    @AppStorage(AppSettings.backupSnoozeKey) private var backupSnooze = 0.0

    private var lastPlayed: [Song] {
        songs.filter { $0.lastPlayedAt != nil }.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }
    private var suggestions: [Pack] { packs.filter { !$0.confirmed } }
    private var favorites: [Song] { songs.filter(\.isFavorite) }
    private var shelfSongs: [ShelfSong] {
        songs.map { ShelfSong(id: $0.id, playCount: $0.playCount, lastPlayedAt: $0.lastPlayedAt, dateAdded: $0.dateAdded, isFavorite: $0.isFavorite) }
    }
    private func resolveSongs(_ ids: [UUID]) -> [Song] {
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }
    private var mostPlayed: [Song] { songs.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount } }

    private var backupDue: Bool {
        BackupReminder.isDue(
            songCount: songs.count,
            lastBackup: lastBackup > 0 ? Date(timeIntervalSince1970: lastBackup) : nil,
            libraryStarted: songs.map(\.dateAdded).min(),
            snoozedUntil: backupSnooze > 0 ? Date(timeIntervalSince1970: backupSnooze) : nil
        )
    }

    private var backupCard: some View {
        let days = BackupReminder.daysSince(lastBackup > 0 ? Date(timeIntervalSince1970: lastBackup) : nil)
        return HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.timemachine").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Time for a Backup").font(.subheadline.weight(.semibold))
                Group {
                    if let days { Text("Last backup \(days) days ago") } else { Text("You have not backed up your library yet.") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Back Up") { showBackupTools = true }.buttonStyle(.borderedProminent).controlSize(.small)
            Button { withAnimation { backupSnooze = BackupReminder.snoozeDate().timeIntervalSince1970 } } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Remind me later")
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
    }

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label("No Music Yet", systemImage: "music.note")
                    } description: {
                        Text("Import songs from the Files app to build your library.")
                    } actions: {
                        Button { showImporter = true } label: { Label("Import Music", systemImage: "square.and.arrow.down") }.eraProminentButton()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            if backupDue { backupCard }
                            if let resume = lastPlayed.first {
                                resumeCard(resume)
                            }
                            if !lastPlayed.isEmpty { shelf(String(localized: "Recently Played"), songs: lastPlayed) }
                            if !favorites.isEmpty { shelf(String(localized: "Favorites"), songs: favorites) }
                            if mostPlayed.count > 1 { shelf(String(localized: "Most Played"), songs: mostPlayed) }
                            let rediscover = resolveSongs(HomeShelves.rediscover(shelfSongs, limit: 12))
                            if rediscover.count >= 3 { shelf(String(localized: "Rediscover"), songs: rediscover) }
                            let unheard = resolveSongs(HomeShelves.neverPlayed(shelfSongs, limit: 12))
                            if unheard.count >= 3 { shelf(String(localized: "Not Played Yet"), songs: unheard) }
                            shelf(String(localized: "Recently Imported"), songs: Array(songs.prefix(10)))
                            if !suggestions.isEmpty { suggestionsRow }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Era")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showStats = true } label: {
                        Label("Listening Stats", systemImage: "chart.bar.fill")
                    }
                }
            }
            .sheet(isPresented: $showBackupTools) {
                NavigationStack {
                    LibraryToolsView()
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showBackupTools = false } } }
                }
            }
            .sheet(isPresented: $showStats) { NavigationStack { StatsView() } }
            .sheet(isPresented: $showImporter) {
                DocumentPicker(contentTypes: ImportManager.importableTypes) { urls in
                    showImporter = false
                    guard !urls.isEmpty else { return }
                    Task { await importer.importFiles(urls, into: store) }
                } onCancel: { showImporter = false }
            }
        }
    }

    private func resumeCard(_ song: Song) -> some View {
        Button {
            if let v = song.primaryVersion {
                player.play(v, from: [v])
                if song.resumePosition > 10 && song.resumePosition < max(0, v.duration - 10) {
                    player.seek(song.resumePosition)
                }
            }
            showNowPlaying = true
        } label: {
            HStack(spacing: 14) {
                Artwork(song: song, radius: 12).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue Listening").font(.caption).foregroundStyle(.secondary)
                    Text(song.title).font(.headline).lineLimit(1)
                    Text(song.displayArtist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.tint)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func shelf(_ title: String, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(songs) { song in
                        Button {
                            // The shelf becomes the queue, so playback continues with its next songs.
                            if let v = song.primaryVersion { player.play(v, from: songs.compactMap(\.primaryVersion)) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Artwork(song: song, radius: 12).frame(width: 150, height: 150)
                                Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(song.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 150, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { SongContextMenu(song: song, showNowPlaying: $showNowPlaying) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var suggestionsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pack Suggestions").font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestions) { pack in
                        Button {
                            pack.confirmed = true
                            store.save()
                        } label: {
                            Label(pack.name, systemImage: "plus.square.stack")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

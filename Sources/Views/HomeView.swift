import SwiftUI
import SwiftData

private struct HomeMix: Identifiable {
    let kind: MixKind
    let songs: [Song]
    var id: String { kind.rawValue }
}

struct HomeView: View {
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore
    @Query(sort: \Song.dateAdded, order: .reverse) private var songs: [Song]
    @Query private var packs: [Pack]
    @Query(sort: \PlayEvent.date, order: .reverse) private var events: [PlayEvent]
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
        songs.map { ShelfSong(id: $0.id, playCount: $0.playCount, lastPlayedAt: $0.lastPlayedAt, dateAdded: $0.dateAdded, isFavorite: $0.isFavorite, rating: $0.rating) }
    }
    private func resolveSongs(_ ids: [UUID]) -> [Song] {
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }
    /// Mixes that are big enough to be worth a tile, each resolved to songs.
    private func mixes() -> [HomeMix] {
        MixKind.allCases.compactMap { kind in
            let list = MixPlaylist.songs(kind, in: songs)
            return list.count >= MixBuilder.minimumSize ? HomeMix(kind: kind, songs: list) : nil
        }
    }

    private var mostPlayed: [Song] { songs.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount } }

    private func throwbackTitle(_ years: Int) -> String {
        years == 1 ? String(localized: "This Time Last Year") : String(localized: "\(years) Years Ago")
    }

    /// Events are sorted newest first, so only the last two weeks need to be mapped.
    private var weeklyRecap: WeeklyRecap {
        let cutoff = Calendar.current.date(byAdding: .day, value: -15, to: Date()) ?? .distantPast
        let recent = events.prefix { $0.date >= cutoff }
            .map { PlayRecord(date: $0.date, seconds: $0.seconds, title: $0.title, artist: $0.artist) }
        return WeeklyRecap.make(from: recent)
    }

    private func mixTitle(_ kind: MixKind) -> String {
        switch kind {
        case .daily: String(localized: "Daily Mix")
        case .deepCuts: String(localized: "Deep Cuts")
        case .fresh: String(localized: "Fresh Imports")
        }
    }

    private func mixSubtitle(_ kind: MixKind) -> String {
        switch kind {
        case .daily: String(localized: "Favorites and forgotten songs")
        case .deepCuts: String(localized: "Rarely played")
        case .fresh: String(localized: "New in your library")
        }
    }

    private func mixSymbol(_ kind: MixKind) -> String {
        switch kind {
        case .daily: "sun.max.fill"
        case .deepCuts: "circle.dotted.circle"
        case .fresh: "sparkles"
        }
    }

    private func mixTint(_ kind: MixKind) -> Color {
        switch kind {
        case .daily: .orange
        case .deepCuts: .indigo
        case .fresh: .teal
        }
    }

    private func mixesRow(_ mixes: [HomeMix]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mixes").font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(mixes) { mix in
                        Button {
                            if let first = mix.songs.first?.primaryVersion {
                                player.play(first, from: mix.songs.compactMap(\.primaryVersion))
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Image(systemName: mixSymbol(mix.kind)).font(.title2).foregroundStyle(.white.opacity(0.95))
                                Spacer(minLength: 6)
                                Text(mixTitle(mix.kind)).font(.headline).foregroundStyle(.white)
                                Text(mixSubtitle(mix.kind)).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                                Text("\(mix.songs.count) songs · \(TimeFormatting.spoken(mix.songs.reduce(0) { $0 + $1.duration }))")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.75))
                            }
                            .padding(14)
                            .frame(width: 170, height: 130, alignment: .leading)
                            .background(
                                LinearGradient(colors: [mixTint(mix.kind), mixTint(mix.kind).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(Text("Plays this mix"))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func recapCard(_ recap: WeeklyRecap) -> some View {
        Button { showStats = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This Week").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if recap.streak > 1 {
                        Label("\(recap.streak) days", systemImage: "flame.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            .labelStyle(.titleAndIcon)
                    }
                }
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(TimeFormatting.spoken(recap.seconds)).font(.title.weight(.bold)).monospacedDigit()
                        trendText(recap.trend)
                    }
                    Spacer(minLength: 8)
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(recap.days) { day in
                            Capsule()
                                .fill(day.seconds > 0 ? Color.accentColor : Color(.tertiarySystemFill))
                                .frame(width: 9, height: max(6, 44 * recap.barHeight(for: day)))
                        }
                    }
                    .frame(height: 44, alignment: .bottom)
                    .accessibilityHidden(true)
                }
                if let top = recap.topTrack {
                    Text("Top track: \(top.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens listening stats"))
    }

    @ViewBuilder private func trendText(_ trend: WeeklyRecap.Trend) -> some View {
        switch trend {
        case .firstWeek: Text("\(weeklyRecap.plays) plays").font(.footnote).foregroundStyle(.secondary)
        case .same: Text("Same as last week").font(.footnote).foregroundStyle(.secondary)
        case .up(let percent): Text("\(percent)% more than last week").font(.footnote).foregroundStyle(.green)
        case .down(let percent): Text("\(percent)% less than last week").font(.footnote).foregroundStyle(.secondary)
        }
    }

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
                            let recap = weeklyRecap
                            if recap.hasActivity { recapCard(recap) }
                            let mixList = mixes()
                            if !mixList.isEmpty { mixesRow(mixList) }
                            if !lastPlayed.isEmpty { shelf(String(localized: "Recently Played"), songs: lastPlayed, linksToHistory: true) }
                            if !favorites.isEmpty { shelf(String(localized: "Favorites"), songs: favorites) }
                            if mostPlayed.count > 1 { shelf(String(localized: "Most Played"), songs: mostPlayed) }
                            let topRated = resolveSongs(HomeShelves.topRated(shelfSongs, limit: 12))
                            if topRated.count >= 3 { shelf(String(localized: "Top Rated"), songs: topRated) }
                            let rediscover = resolveSongs(HomeShelves.rediscover(shelfSongs, limit: 12))
                            if rediscover.count >= 3 { shelf(String(localized: "Rediscover"), songs: rediscover) }
                            let unheard = resolveSongs(HomeShelves.neverPlayed(shelfSongs, limit: 12))
                            if unheard.count >= 3 { shelf(String(localized: "Not Played Yet"), songs: unheard) }
                            if let throwback = HomeShelves.throwback(shelfSongs) {
                                let older = resolveSongs(throwback.ids)
                                if !older.isEmpty { shelf(throwbackTitle(throwback.yearsAgo), songs: older) }
                            }
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

    private func shelf(_ title: String, songs: [Song], linksToHistory: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title2.bold())
                Spacer()
                if linksToHistory {
                    NavigationLink { HistoryView() } label: {
                        HStack(spacing: 3) { Text("History"); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
                            .font(.subheadline)
                    }
                    .accessibilityLabel("Listening History")
                }
            }
            .padding(.horizontal)
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

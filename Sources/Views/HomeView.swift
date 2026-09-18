import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var showNowPlaying: Bool
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore
    @Query(sort: \Song.dateAdded, order: .reverse) private var songs: [Song]
    @Query private var packs: [Pack]
    @State private var showStats = ProcessInfo.processInfo.arguments.contains("--era-stats")

    private var lastPlayed: [Song] {
        songs.filter { $0.lastPlayedAt != nil }.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }
    private var suggestions: [Pack] { packs.filter { !$0.confirmed } }
    private var favorites: [Song] { songs.filter(\.isFavorite) }
    private var mostPlayed: [Song] { songs.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount } }

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label("No Music Yet", systemImage: "music.note")
                    } description: {
                        Text("Import songs from the Files app to build your library.")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            if let resume = lastPlayed.first {
                                resumeCard(resume)
                            }
                            if !lastPlayed.isEmpty { shelf(String(localized: "Recently Played"), songs: lastPlayed) }
                            if !favorites.isEmpty { shelf(String(localized: "Favorites"), songs: favorites) }
                            if mostPlayed.count > 1 { shelf(String(localized: "Most Played"), songs: mostPlayed) }
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
            .sheet(isPresented: $showStats) { NavigationStack { StatsView() } }
        }
    }

    private func resumeCard(_ song: Song) -> some View {
        Button {
            if let v = song.primaryVersion {
                player.play(v, from: song.sortedVersions)
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
                            if let v = song.primaryVersion { player.play(v, from: song.sortedVersions) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Artwork(song: song, radius: 12).frame(width: 150, height: 150)
                                Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(song.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 150, alignment: .leading)
                        }
                        .buttonStyle(.plain)
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

import SwiftUI
import SwiftData

// "Rate Songs": geht unbewertete Songs der Reihe nach durch, die oft gehoert wurden zuerst.
// Ein Tipp auf einen Stern bewertet und springt zum naechsten Song.
struct RatingReviewView: View {
    @Query private var songs: [Song]
    @EnvironmentObject private var store: EraStore
    @EnvironmentObject private var player: PlayerEngine
    @State private var queue: [UUID] = []
    @State private var position = 0
    @State private var ratedCount = 0
    @State private var loaded = false

    private var current: Song? {
        guard position < queue.count else { return nil }
        return songs.first { $0.id == queue[position] }
    }

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if queue.isEmpty {
                ContentUnavailableView {
                    Label("All Songs Rated", systemImage: "star.fill")
                } description: {
                    Text("Every song in your library has a rating.")
                }
            } else if let song = current {
                card(song)
            } else {
                ContentUnavailableView {
                    Label("All Caught Up", systemImage: "checkmark.circle.fill")
                } description: {
                    Text("Songs rated: \(ratedCount)")
                } actions: {
                    Button("Start Again") { start() }.eraProminentButton()
                }
            }
        }
        .navigationTitle("Rate Songs")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { start() } }
    }

    private func start() {
        let candidates = songs.map {
            RatingCandidate(id: $0.id, rating: $0.rating, playCount: $0.playCount, isFavorite: $0.isFavorite,
                            lastPlayedAt: $0.lastPlayedAt, dateAdded: $0.dateAdded)
        }
        queue = RatingReview.queue(from: candidates)
        position = 0
        ratedCount = 0
        loaded = true
    }

    private func card(_ song: Song) -> some View {
        VStack(spacing: 18) {
            ProgressView(value: Double(position), total: Double(max(queue.count, 1)))
                .padding(.horizontal)
            Text("\(position + 1) of \(queue.count)").font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Artwork(song: song, radius: 18)
                .scaledSquare(240)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            VStack(spacing: 4) {
                Text(song.title).font(.title2.bold()).multilineTextAlignment(.center).lineLimit(2)
                Text(song.displayArtist).font(.body).foregroundStyle(.secondary).lineLimit(1)
                if song.playCount > 0 {
                    Text("Plays: \(song.playCount)").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)
            StarRatingRow(rating: song.rating) { rate(song, $0) }
                .sensoryFeedback(.selection, trigger: song.rating)
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Button { togglePreview(song) } label: {
                    Label(isPreviewing(song) ? String(localized: "Pause") : String(localized: "Play"), systemImage: isPreviewing(song) ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                Button { advance(from: position) } label: {
                    Label("Skip", systemImage: "forward.end.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top)
        .id(song.id)
        .transition(.opacity)
    }

    private func isPreviewing(_ song: Song) -> Bool { player.isPlaying && player.current?.song?.id == song.id }

    private func togglePreview(_ song: Song) {
        if player.current?.song?.id == song.id { player.toggle() }
        else if let version = song.primaryVersion { player.play(version, from: [version]) }
    }

    private func rate(_ song: Song, _ value: Int) {
        song.rating = SongRating.clamp(value)
        store.save()
        guard song.rating > 0 else { return }
        ratedCount += 1
        let at = position
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            advance(from: at)
        }
    }

    private func advance(from index: Int) {
        guard position == index else { return }
        withAnimation(.easeInOut(duration: 0.2)) { position += 1 }
    }
}

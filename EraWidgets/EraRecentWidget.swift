import WidgetKit
import SwiftUI
import AppIntents

// Home Screen widget: Now Playing with working Play/Pause and Next buttons,
// plus Recently Played with deep links. Data arrives through the App Group
// container; fresh data is pushed via WidgetCenter.reloadAllTimelines().
struct EraRecentProvider: TimelineProvider {
    func placeholder(in context: Context) -> EraRecentEntry {
        EraRecentEntry(date: Date(),
                       nowPlaying: EraShared.NowPlaying(trackID: UUID(), title: "Night Drive", artist: "Nova Lane",
                                                        artwork: nil, isPlaying: true, position: 42, duration: 210,
                                                        updatedAt: Date()),
                       tracks: [EraShared.RecentTrack(id: UUID(), title: "Night Drive", artist: "Nova Lane", artwork: nil)])
    }
    func getSnapshot(in context: Context, completion: @escaping (EraRecentEntry) -> Void) {
        completion(currentEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EraRecentEntry>) -> Void) {
        // Fresh data arrives via WidgetCenter.reloadAllTimelines() from the app.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }
    private func currentEntry() -> EraRecentEntry {
        EraRecentEntry(date: Date(), nowPlaying: EraShared.readNowPlaying(), tracks: EraShared.readRecent())
    }
}

struct EraRecentEntry: TimelineEntry {
    let date: Date
    let nowPlaying: EraShared.NowPlaying?
    let tracks: [EraShared.RecentTrack]
}

struct EraRecentWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: EraRecentEntry

    var body: some View {
        if entry.nowPlaying == nil && entry.tracks.isEmpty {
            emptyState
        } else if family == .systemSmall {
            smallView
        } else {
            mediumView
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Play something in Era")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkImage(name: String?, seed: UUID, size: CGFloat) -> some View {
        if let name, let url = EraShared.artworkURL(name),
           let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        } else {
            VinylDiscView(seed: seed, isPlaying: entry.nowPlaying?.isPlaying ?? false)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        }
    }

    // MARK: - Controls

    private var isPlaying: Bool { entry.nowPlaying?.isPlaying ?? false }

    private var controlButtons: some View {
        HStack(spacing: 14) {
            Button(intent: EraPreviousTrackIntent()) {
                Image(systemName: "backward.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain)
            Button(intent: EraTogglePlayIntent()) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain)
            Button(intent: EraNextTrackIntent()) {
                Image(systemName: "forward.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Small

    private var smallView: some View {
        let title = entry.nowPlaying?.title ?? entry.tracks.first?.title ?? "Era"
        let artist = entry.nowPlaying?.artist ?? entry.tracks.first?.artist ?? ""
        let seed = entry.nowPlaying?.trackID ?? entry.tracks.first?.id ?? UUID()
        let art = entry.nowPlaying?.artwork ?? entry.tracks.first?.artwork
        return ZStack(alignment: .bottom) {
            artworkImage(name: art, seed: seed, size: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(artist).font(.caption2).lineLimit(1).opacity(0.85)
                }
                controlButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.black.opacity(0.45))
        }
        .foregroundStyle(.white)
    }

    // MARK: - Medium

    private var mediumView: some View {
        HStack(spacing: 12) {
            if let now = entry.nowPlaying {
                VStack(alignment: .leading, spacing: 6) {
                    artworkImage(name: now.artwork, seed: now.trackID, size: 74)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(now.title).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(now.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    controlButtons
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Recently Played")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(entry.tracks.prefix(3)) { track in
                    Link(destination: URL(string: "era://song/\(track.id.uuidString)")!) {
                        HStack(spacing: 8) {
                            artworkImage(name: track.artwork, seed: track.id, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title).font(.caption.weight(.medium)).lineLimit(1)
                                Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
                if entry.tracks.isEmpty {
                    Text("Play something in Era")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }
}

struct EraRecentWidget: Widget {
    let kind = "EraRecentWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EraRecentProvider()) { entry in
            EraRecentWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "era://resume"))
        }
        .configurationDisplayName("Now Playing")
        .description("Control playback and jump back into recent tracks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

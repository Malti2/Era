import WidgetKit
import SwiftUI

// Home Screen widget: Recently Played. Tap opens Era and resumes playback,
// medium size also lists the last tracks and deep-links into them.
struct EraRecentProvider: TimelineProvider {
    func placeholder(in context: Context) -> EraRecentEntry {
        EraRecentEntry(date: Date(), tracks: [EraShared.RecentTrack(id: UUID(), title: "Night Drive", artist: "Nova Lane", artwork: nil)])
    }
    func getSnapshot(in context: Context, completion: @escaping (EraRecentEntry) -> Void) {
        completion(EraRecentEntry(date: Date(), tracks: EraShared.readRecent()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EraRecentEntry>) -> Void) {
        // Fresh data arrives via WidgetCenter.reloadAllTimelines() from the app.
        completion(Timeline(entries: [EraRecentEntry(date: Date(), tracks: EraShared.readRecent())], policy: .never))
    }
}

struct EraRecentEntry: TimelineEntry {
    let date: Date
    let tracks: [EraShared.RecentTrack]
}

struct EraRecentWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: EraRecentEntry

    var body: some View {
        if entry.tracks.isEmpty {
            emptyState
        } else if family == .systemSmall {
            smallView(entry.tracks[0])
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
        .widgetURL(URL(string: "era://resume"))
    }

    private func artwork(_ track: EraShared.RecentTrack, size: CGFloat) -> some View {
        Group {
            if let name = track.artwork, let url = EraShared.artworkURL(name),
               let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                VinylDiscView(seed: track.id, spins: false)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }

    private func smallView(_ track: EraShared.RecentTrack) -> some View {
        ZStack(alignment: .bottomLeading) {
            artwork(track, size: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(track.artist).font(.caption2).lineLimit(1).opacity(0.85)
                }
                Spacer()
                Image(systemName: "play.fill").font(.caption)
            }
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(8)
        }
        .widgetURL(URL(string: "era://resume"))
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            Link(destination: URL(string: "era://resume")!) {
                ZStack(alignment: .bottom) {
                    artwork(entry.tracks[0], size: 120)
                    Image(systemName: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(6)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Recently Played")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(entry.tracks.prefix(3)) { track in
                    Link(destination: URL(string: "era://song/\(track.id.uuidString)")!) {
                        HStack(spacing: 8) {
                            artwork(track, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title).font(.caption.weight(.medium)).lineLimit(1)
                                Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
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
        }
        .configurationDisplayName("Recently Played")
        .description("Jump back into your last tracks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

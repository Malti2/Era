import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer
import UIKit

// Artwork: eingebettetes Cover der Version, sonst generierte Disc (Spec 8.1).
struct Artwork: View {
    let song: Song?
    var version: SongVersion?
    var radius: CGFloat = 10
    var carded: Bool = true

    var body: some View {
        let v = version ?? song?.primaryVersion
        if let file = v?.artworkFile,
           let data = try? Data(contentsOf: LibraryFiles.artworkURL(file)),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else if let song {
            DiscArtwork(songID: song.id, statusName: song.statusTags.first?.name, radius: radius, carded: carded)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(.secondarySystemFill))
        }
    }
}

struct SongRow: View {
    let song: Song
    let version: SongVersion?
    var isCurrent: Bool = false

    var body: some View {
        let v = version ?? song.primaryVersion
        HStack(spacing: 12) {
            Artwork(song: song, version: v, radius: 8).frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text((v?.displayTitle.isEmpty == false ? v?.displayTitle : nil) ?? song.title)
                    .font(.body).lineLimit(1)
                HStack(spacing: 4) {
                    if let v, song.versions.count > 1 {
                        Text(v.name)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                    Text(song.displayArtist)
                    if !song.album.isEmpty { Text("· \(song.album)") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            } else {
                Text(v?.durationText ?? "")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerEngine
    let open: () -> Void

    var body: some View {
        if let version = player.current, let song = version.song {
            HStack(spacing: 10) {
                Artwork(song: song, version: version, radius: 7).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(version.displayTitle).font(.subheadline).lineLimit(1)
                    Text(version.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 40).contentShape(Rectangle())
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .frame(width: 36, height: 40).contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .eraGlassRect(18)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
        }
    }
}

struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .secondaryLabel
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// Nativer Lautstaerke-Slider (MediaPlayer.MPVolumeView, wie in Apple Music).
struct VolumeSlider: UIViewRepresentable {
    final class Coordinator: NSObject {
        let systemView = MPVolumeView(frame: .zero)
        weak var displaySlider: UISlider?
        var systemSlider: UISlider? { systemView.subviews.compactMap { $0 as? UISlider }.first }

        @objc func changed(_ sender: UISlider) {
            systemSlider?.setValue(sender.value, animated: false)
            systemSlider?.sendActions(for: .valueChanged)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.minimumTrackTintColor = .label
        slider.maximumTrackTintColor = .tertiaryLabel
        slider.value = AVAudioSession.sharedInstance().outputVolume
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        context.coordinator.systemView.showsRouteButton = false
        context.coordinator.systemView.isHidden = true
        slider.addSubview(context.coordinator.systemView)
        context.coordinator.displaySlider = slider
        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        if !uiView.isTracking { uiView.value = AVAudioSession.sharedInstance().outputVolume }
    }
}

// Natives iOS-Share-Sheet fuer Audiodateien (UIActivityViewController).
struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

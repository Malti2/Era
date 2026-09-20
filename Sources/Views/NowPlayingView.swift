import SwiftUI

// Now Playing als Sheet (Apple-Music-Stil), kein eigener Tab (Spec 13.4).

private enum ArtworkColor {
    @MainActor
    static func tint(for song: Song, version: SongVersion) -> Color {
        let image: UIImage
        if let file = version.artworkFile,
           let data = try? Data(contentsOf: LibraryFiles.artworkURL(file)),
           let stored = UIImage(data: data) {
            image = stored
        } else {
            image = DiscArtworkCache.png(for: song.id, status: song.statusTags.first?.name, size: 96)
        }
        return Color(uiColor: mutedAverage(of: image))
    }

    private static func mutedAverage(of image: UIImage) -> UIColor {
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        let sample = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = sample.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return UIColor(white: 0.12, alpha: 1)
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var weight: CGFloat = 0
        let count = cgImage.width * cgImage.height
        for index in 0..<count {
            // UIGraphicsImageRenderer uses BGRA byte order on iOS. Ignore nearly
            // white highlights so a coloured cover does not wash out to grey.
            let offset = index * 4
            let b = CGFloat(bytes[offset]) / 255
            let g = CGFloat(bytes[offset + 1]) / 255
            let r = CGFloat(bytes[offset + 2]) / 255
            let maximum = max(r, g, b)
            let minimum = min(r, g, b)
            let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
            let pixelWeight = maximum > 0.92 && saturation < 0.10 ? 0.12 : 0.55 + saturation
            red += r * pixelWeight
            green += g * pixelWeight
            blue += b * pixelWeight
            weight += pixelWeight
        }
        guard weight > 0 else { return UIColor(white: 0.12, alpha: 1) }

        let average = UIColor(red: red / weight, green: green / weight, blue: blue / weight, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        if saturation < 0.07 {
            return UIColor(white: min(0.26, max(0.12, brightness * 0.34)), alpha: 1)
        }
        return UIColor(
            hue: hue,
            saturation: min(0.58, max(0.22, saturation * 0.85)),
            brightness: min(0.42, max(0.24, brightness * 0.52)),
            alpha: 1
        )
    }
}

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var store: EraStore
    @State private var showQueue = false
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showTimer = false
    @State private var confirmClearQueue = false
    @State private var queueEditing = false
    @State private var artworkTint = Color(white: 0.10)
    @AppStorage(AppSettings.skipIntervalKey) private var skipInterval = 15
    @AppStorage(AppSettings.hapticsEnabledKey) private var haptics = true

    init() {
        if ProcessInfo.processInfo.arguments.contains("--era-queue") {
            _showQueue = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let version = player.current, let song = version.song {
                    content(version, song)
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "play.circle", description: Text("Choose a song from your library"))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
            }
            .sheet(isPresented: $showQueue) { queueSheet }
            .sheet(isPresented: $showTimer) { timerSheet }
            .background {
                // Tastaturkurzbefehle (iPad/Mac): Leertaste + Pfeile, unsichtbar
                Group {
                    Button("") { player.toggle() }.keyboardShortcut(.space, modifiers: [])
                    Button("") { player.next() }.keyboardShortcut(.rightArrow, modifiers: [])
                    Button("") { player.previous() }.keyboardShortcut(.leftArrow, modifiers: [])
                }
                .hidden()
                .accessibilityHidden(true)
            }
        }
    }

    private func content(_ version: SongVersion, _ song: Song) -> some View {
        GeometryReader { geometry in
            // The sheet's safe area tops out near 740pt even on large iPhones, so the
            // compact guard must only trigger on genuinely small screens (SE-class).
            let compact = geometry.size.height < 700
            let artworkSize = min(geometry.size.width - 60, compact ? 250 : 330)

            ZStack {
                playerBackground

                VStack(spacing: 0) {
                    Capsule()
                        .fill(.secondary.opacity(0.55))
                        .frame(width: 38, height: 5)
                        .padding(.top, 8)

                    Artwork(song: song, version: version, radius: 18, carded: false)
                        .frame(width: artworkSize, height: artworkSize)
                        .scaleEffect(player.isPlaying ? 1 : 0.94)
                        .animation(.spring(response: 0.45), value: player.isPlaying)
                        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
                        .padding(.top, compact ? 16 : 24)

                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(version.displayTitle)
                                    .font(.title3.bold())
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(0.82)
                                    .layoutPriority(1)
                                if song.tags.contains(where: { $0.name == "Explicit" }) {
                                    Text("E")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                                        .fixedSize()
                                }
                            }
                            Text(version.displayArtist)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()

                        Button { song.isFavorite.toggle(); store.save() } label: {
                            Image(systemName: song.isFavorite ? "star.fill" : "star")
                                .font(.title2)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 36, height: 44)
                        }
                        .sensoryFeedback(.impact(flexibility: .soft), trigger: song.isFavorite) { _, _ in haptics }

                        Menu {
                            ForEach(song.sortedVersions) { v in
                                Button { player.switchVersion(v) } label: {
                                    Label(v.name, systemImage: v.id == version.id ? "checkmark" : "opticaldisc")
                                }
                                .disabled(v.id == version.id)
                            }
                            Divider()
                            Button { showTimer = true } label: { Label("Sleep Timer", systemImage: "moon.zzz") }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title2)
                                .frame(width: 36, height: 44)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 30)
                    .padding(.top, compact ? 16 : 22)

                    // Keep transport controls anchored to the bottom like Apple Music.
                    // Any extra height becomes breathing room between metadata and controls,
                    // instead of collecting as an empty block below the controls.
                    Spacer(minLength: compact ? 10 : 20)

                    VStack(spacing: 0) {
                        VStack(spacing: 5) {
                            Slider(value: Binding(
                                get: { scrubbing ? scrubValue : player.currentTime },
                                set: { scrubValue = $0 }
                            ), in: 0...max(1, player.duration)) { editing in
                            if editing {
                                scrubValue = player.currentTime
                                scrubbing = true
                            } else {
                                scrubbing = false
                                player.seek(scrubValue)
                            }
                        }
                        .tint(.primary)

                        HStack {
                            Text(TimeFormatting.mmss(scrubbing ? scrubValue : player.currentTime))
                            Spacer()
                            Menu {
                                ForEach(song.sortedVersions) { v in
                                    Button { player.switchVersion(v) } label: {
                                        Label(v.name, systemImage: v.id == version.id ? "checkmark" : "opticaldisc")
                                    }
                                }
                            } label: {
                                Label("Version: \(version.name)", systemImage: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial, in: .capsule)
                            }
                            Spacer()
                            Text("-" + TimeFormatting.mmss(max(0, player.duration - (scrubbing ? scrubValue : player.currentTime))))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                        .padding(.horizontal, 30)

                        HStack {
                            Button { player.previous() } label: { Image(systemName: "backward.fill") }
                        Spacer()
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Spacer()
                        Button { player.next() } label: { Image(systemName: "forward.fill") }
                    }
                        .font(.system(size: compact ? 32 : 36, weight: .semibold))
                        .padding(.horizontal, 66)
                        .padding(.top, compact ? 14 : 20)

                        HStack(spacing: 10) {
                            Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                        VolumeSlider().frame(height: 28)
                        Image(systemName: "speaker.wave.3.fill").font(.body).foregroundStyle(.secondary)
                    }
                        .padding(.horizontal, 30)
                        .padding(.top, compact ? 12 : 18)

                        HStack {
                            Menu {
                            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                                Button { player.setRate(Float(r)) } label: {
                                    if Float(r) == player.rate { Label("\(String(format: "%g", r))x", systemImage: "checkmark") }
                                    else { Text("\(String(format: "%g", r))x") }
                                }
                            }
                        } label: {
                            Text(player.rate == 1.0 ? "1x" : "\(String(format: "%g", player.rate))x")
                                .font(.subheadline.bold()).frame(width: 40, height: 40)
                        }
                        Spacer()
                        AirPlayRouteButton().frame(width: 40, height: 40)
                        Spacer()
                        control("list.bullet", active: showQueue) { showQueue = true }
                    }
                        .padding(.horizontal, 75)
                        .padding(.top, compact ? 6 : 10)
                    }
                    .padding(.bottom, max(8, geometry.safeAreaInsets.bottom + 4))
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .foregroundStyle(.white)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: version.id) {
            let nextTint = ArtworkColor.tint(for: song, version: version)
            withAnimation(.easeInOut(duration: 0.55)) {
                artworkTint = nextTint
            }
        }
    }

    private var playerBackground: some View {
        ZStack {
            // Keep a dark neutral foundation and mix the cover colour in lightly.
            // This gives the whole player Apple Music's calm artwork tint without
            // sacrificing white-text contrast on unusually bright covers.
            Color(white: 0.055)
            artworkTint.opacity(0.34)
            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.32)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.easeInOut(duration: 0.55), value: artworkTint)
        .ignoresSafeArea()
    }

    private func control(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
        }
    }

    // "Up Next" mit nativem Bearbeiten: Verschieben, Entfernen, Leeren.
    private var queueSheet: some View {
        NavigationStack {
            List {
                ForEach(player.queue, id: \.id) { v in
                    HStack {
                        if let song = v.song { SongRow(song: song, version: v, isCurrent: player.current?.id == v.id) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { player.play(v, from: player.queue) }
                }
                .onMove { player.moveInQueue(from: $0, to: $1) }
                .onDelete { player.removeFromQueue(at: $0) }
            }
            .navigationTitle("Up Next")
            .environment(\.editMode, .constant(queueEditing ? .active : .inactive))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(queueEditing ? "Done Editing" : "Edit") { queueEditing.toggle() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { showQueue = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    if player.queue.count > 1 {
                        Menu {
                            Button("Clear Queue", role: .destructive) { confirmClearQueue = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Clear Queue?", isPresented: $confirmClearQueue, titleVisibility: .visible) {
                Button("Clear Queue", role: .destructive) { player.clearQueue() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All tracks except the current one will be removed from the queue.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var timerSheet: some View {
        NavigationStack {
            List {
                if let r = player.sleepRemaining {
                    Section {
                        Text("Remaining \(r / 60):\(String(format: "%02d", r % 60))").font(.title.bold())
                        Button("Stop Timer", role: .destructive) { player.cancelSleep(); showTimer = false }
                    }
                }
                Section("Stop Playback After") {
                    ForEach([5, 10, 15, 30, 45, 60], id: \.self) { m in
                        Button("\(m) Minutes") { player.setSleep(minutes: m); showTimer = false }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
        }
        .presentationDetents([.medium])
    }
}

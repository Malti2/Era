import SwiftUI

// Now Playing als Sheet (Apple-Music-Stil), kein eigener Tab (Spec 13.4).
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
        ZStack {
            playerBackground(song: song, version: version)
            VStack(spacing: 0) {
                Capsule().fill(.secondary.opacity(0.55)).frame(width: 38, height: 5).padding(.top, 8)
                Spacer(minLength: 20)
                Artwork(song: song, version: version, radius: 14)
                    .frame(maxWidth: 330).aspectRatio(1, contentMode: .fit)
                    .scaleEffect(player.isPlaying ? 1 : 0.92)
                    .animation(.spring(response: 0.45), value: player.isPlaying)
                    .shadow(color: .black.opacity(0.32), radius: 30, y: 16)
                    .padding(.horizontal, 30)
                Spacer(minLength: 24)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(version.displayTitle).font(.title3.bold()).lineLimit(1)
                            if song.tags.contains(where: { $0.name == "Explicit" }) {
                                Text("E").font(.caption2.bold()).padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        Text(version.displayArtist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { song.isFavorite.toggle(); store.save() } label: {
                        Image(systemName: song.isFavorite ? "star.fill" : "star")
                            .font(.title2).contentTransition(.symbolEffect(.replace))
                    }
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: song.isFavorite) { _, _ in haptics }
                    Menu {
                        ForEach(song.sortedVersions) { v in
                            Button {
                                player.switchVersion(v)
                            } label: { Label(v.name, systemImage: v.id == version.id ? "checkmark" : "opticaldisc") }
                            .disabled(v.id == version.id)
                        }
                        Divider()
                        Button { showTimer = true } label: { Label("Sleep Timer", systemImage: "moon.zzz") }
                    } label: { Image(systemName: "ellipsis").font(.title2).frame(width: 44, height: 44) }
                }
                .padding(.horizontal, 30)

                VStack(spacing: 6) {
                    // Scrubbing runs on local state while dragging: the 0.25s
                    // ticker keeps publishing currentTime and would otherwise
                    // yank the knob back mid-drag, and every intermediate
                    // value used to trigger a full seek (cancel + reprepare
                    // the next track) dozens of times per second. The real
                    // seek fires once, when the drag ends.
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
                    ZStack {
                        HStack {
                            Text(TimeFormatting.mmss(scrubbing ? scrubValue : player.currentTime))
                            Spacer()
                            Text("-" + TimeFormatting.mmss(max(0, player.duration - (scrubbing ? scrubValue : player.currentTime))))
                        }
                        Menu {
                            ForEach(song.sortedVersions) { v in
                                Button { player.switchVersion(v) } label: { Label(v.name, systemImage: v.id == version.id ? "checkmark" : "opticaldisc") }
                            }
                        } label: {
                            Label("Version: \(version.name)", systemImage: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: .capsule)
                        }
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 30).padding(.top, 22)

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
                .font(.system(size: 38, weight: .semibold))
                .padding(.horizontal, 65).padding(.top, 26)

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                    VolumeSlider().frame(height: 28)
                    Image(systemName: "speaker.wave.3.fill").font(.body).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 30).padding(.top, 26)

                HStack {
                    Menu {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                            Button {
                                player.setRate(Float(r))
                            } label: {
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
                .padding(.horizontal, 75).padding(.top, 22).padding(.bottom, 16)
            }
        }
        .foregroundStyle(.primary)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func playerBackground(song: Song, version: SongVersion) -> some View {
        ZStack {
            Color(.systemBackground)
            Artwork(song: song, version: version, radius: 0)
                .scaleEffect(1.9).blur(radius: 72).opacity(0.42)
            LinearGradient(colors: [.clear, Color(.systemBackground).opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
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

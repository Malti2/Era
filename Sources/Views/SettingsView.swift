import SwiftUI
import SwiftData

// Apple-Stil: App-Icon + Versionsnummer, gruppierte Liste, nur echte Einstellungen.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @Query private var songs: [Song]
    @Query private var versions: [SongVersion]

    @AppStorage(AppSettings.defaultRateKey) private var defaultRate = 1.0
    @AppStorage(AppSettings.skipIntervalKey) private var skipInterval = 15
    @AppStorage(AppSettings.pauseOnRouteChangeKey) private var pauseOnRouteChange = true
    @AppStorage(AppSettings.resumeAfterInterruptionKey) private var resumeAfterInterruption = true
    @AppStorage(AppSettings.hapticsEnabledKey) private var haptics = true
    @AppStorage(AppSettings.spotlightEnabledKey) private var spotlightEnabled = true
    @AppStorage(AppSettings.crackleEnabledKey) private var crackleEnabled = false
    @AppStorage(AppSettings.crackleVolumeKey) private var crackleVolume = 0.18
    @AppStorage(AppSettings.transitionStyleKey) private var transitionStyle = "off"
    @AppStorage(AppSettings.crossfadeSecondsKey) private var crossfadeSeconds = 6

    @State private var spotlightRebuilt = false
    @State private var backupItem: ShareItem?
    @State private var backupError = false
    @State private var showOnboarding = false
    @State private var confirmReset = false
    @State private var resetDone = false
    @StateObject private var updater = UpdateService()
    @State private var updateShareItem: ShareItem?

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "27.0.0"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(uiImage: AppIconImage.uiImage)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Era").font(.title3.weight(.semibold))
                            Text("Version \(appVersion) (\(buildNumber))").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Playback") {
                    Picker(selection: $defaultRate) {
                        ForEach(AppSettings.rates, id: \.self) { r in
                            Text(r.formatted() + "×").tag(r)
                        }
                    } label: {
                        Label("Default Speed", systemImage: "metronome")
                    }
                    Picker(selection: $skipInterval) {
                        ForEach(AppSettings.skipIntervals, id: \.self) { v in
                            Text("\(v) sec").tag(v)
                        }
                    } label: {
                        Label("Skip Distance", systemImage: "goforward.15")
                    }
                    Toggle(isOn: $pauseOnRouteChange) {
                        Label("Pause when headphones disconnect", systemImage: "headphones")
                    }
                    Toggle(isOn: $resumeAfterInterruption) {
                        Label("Resume after calls", systemImage: "phone.fill")
                    }
                    NavigationLink { AudioEffectsSettingsView() } label: { Label("Audio Effects", systemImage: "waveform") }
                    Toggle(isOn: $haptics) {
                        Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }
                Section("Stats") {
                    NavigationLink {
                        StatsView(showsDoneButton: false)
                    } label: {
                        Label("Listening Stats", systemImage: "chart.bar.fill")
                    }
                }
                Section("Library") {
                    LabeledContent("Storage Location", value: "Stored Locally on This iPhone")
                    LabeledContent("Songs", value: "\(songs.count)")
                    LabeledContent("Versions", value: "\(versions.count)")
                    LabeledContent("Storage Used", value: LibraryFiles.librarySizeText())
                }
                Section("Library & Backup") {
                    Button {
                        do {
                            backupItem = ShareItem(url: try BackupService.exportURL(store: store))
                        } catch {
                            backupError = true
                        }
                    } label: {
                        Label("Export Library (JSON)", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                Section("Search & Siri") {
                    Toggle(isOn: $spotlightEnabled) {
                        Label("Show in Spotlight Search", systemImage: "magnifyingglass")
                    }
                    .onChange(of: spotlightEnabled) { _, on in
                        if on {
                            SpotlightIndexer.reindex(songs: songs)
                        } else {
                            SpotlightIndexer.clearAll()
                        }
                    }
                    Button {
                        SpotlightIndexer.reindex(songs: songs)
                        spotlightRebuilt = true
                    } label: {
                        Label("Rebuild Spotlight Index", systemImage: spotlightRebuilt ? "checkmark.circle.fill" : "arrow.clockwise")
                    }
                    .disabled(!spotlightEnabled)
                    Text("Siri: “Play with Era”, “pause”, “next”").font(.footnote).foregroundStyle(.secondary)
                }
                Section("About & Updates") {
                    NavigationLink { List { updateContent }.navigationTitle("Updates") } label: { Label("Updates", systemImage: "arrow.down.circle") }
                    Button { showOnboarding = true } label: { Label("Show Introduction Again", systemImage: "sparkles") }
                    LabeledContent("Privacy", value: "Everything local, no tracking")
                }
                Section("Reset") {
                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("Delete All Data", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $backupItem) { item in ShareSheet(items: [item.url]) }
            .sheet(item: $updateShareItem) { item in ShareSheet(items: [item.url]) }
            .sheet(isPresented: $showOnboarding) { OnboardingView() }
            .alert("Backup Failed", isPresented: $backupError) {
                Button("OK", role: .cancel) {}
            }
            .confirmationDialog("Reset Era Completely?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete All Songs and Data", role: .destructive) {
                    store.resetEverything()
                    showOnboarding = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Songs, versions, playlists, tags, packs, settings, and local audio files will be permanently deleted.")
            }
        }
    }

    private var updateFooter: String {
        "Era downloads the latest unsigned IPA directly from GitHub. Use the share sheet to open it in your sideloading app. iOS does not let Era install or replace its own app binary."
    }

    @ViewBuilder
    private var updateSection: some View {
        Section {
            updateContent
        } header: {
            Text("Updates")
        } footer: {
            Text(updateFooter)
        }
    }

    @ViewBuilder
    private var updateContent: some View {
        switch updater.state {
        case .idle:
            Button {
                Task { await updater.check(currentVersion: appVersion) }
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
        case .checking:
            HStack {
                ProgressView()
                Text("Checking GitHub Releases…")
            }
        case .upToDate:
            Label("Era is up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button("Check Again") {
                Task { await updater.check(currentVersion: appVersion) }
            }
        case .available(let release):
            LabeledContent("Update Available", value: release.version)
            Button {
                Task { await updater.download(release) }
            } label: {
                Label("Download IPA", systemImage: "arrow.down.circle.fill")
            }
        case .downloading(let release, _):
            HStack {
                ProgressView()
                Text("Downloading Era \(release.version)…")
            }
        case .downloaded(let release, let url):
            Label("Era \(release.version) downloaded", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button {
                updateShareItem = ShareItem(url: url)
            } label: {
                Label("Open in Sideloading App", systemImage: "square.and.arrow.up")
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Button("Try Again") {
                Task { await updater.check(currentVersion: appVersion) }
            }
        }
    }
}

private struct AudioEffectsSettingsView: View {
    @AppStorage(AppSettings.transitionStyleKey) private var transitionStyle = "off"
    @AppStorage(AppSettings.crossfadeSecondsKey) private var crossfadeSeconds = 6
    @AppStorage(AppSettings.crackleEnabledKey) private var crackleEnabled = false
    @AppStorage(AppSettings.crackleVolumeKey) private var crackleVolume = 0.18
    var body: some View {
        Form {
            Section("Transitions") {
                Picker("Style", selection: $transitionStyle) {
                    ForEach(AppSettings.TransitionStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if transitionStyle == "crossfade" {
                    Picker("Duration", selection: $crossfadeSeconds) { ForEach(AppSettings.crossfadeOptions, id: \.self) { Text("\($0) sec").tag($0) } }
                }
            }
            Section("Vinyl Crackle") {
                Toggle("Enabled", isOn: $crackleEnabled)
                if crackleEnabled { Slider(value: $crackleVolume, in: 0.02...0.5) }
            }
        }.navigationTitle("Audio Effects")
    }
}

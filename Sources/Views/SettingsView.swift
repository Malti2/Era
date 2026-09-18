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
                    Picker(selection: $transitionStyle) {
                        ForEach(AppSettings.TransitionStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    } label: {
                        Label("Transitions", systemImage: "arrow.triangle.swap")
                    }
                    if transitionStyle == "crossfade" {
                        Picker(selection: $crossfadeSeconds) {
                            ForEach(AppSettings.crossfadeOptions, id: \.self) { v in
                                Text("\(v) sec").tag(v)
                            }
                        } label: {
                            Label("Crossfade Duration", systemImage: "timer")
                        }
                    }
                    Toggle(isOn: $crackleEnabled) {
                        Label("Vinyl Crackle", systemImage: "opticaldisc")
                    }
                    if crackleEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Crackle Volume", systemImage: "speaker.wave.2")
                            Slider(value: $crackleVolume, in: 0.02...0.5)
                        }
                    }
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
                Section("Backup") {
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
                    Label("Siri: “Play with Era”, “pause”, “next”", systemImage: "mic.fill")
                }
                updateSection
                Section("Reset") {
                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("Delete All Data", systemImage: "trash")
                    }
                }
                Section("About Era") {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Show Introduction Again", systemImage: "sparkles")
                    }
                    LabeledContent("Privacy", value: "Everything local, no tracking")
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

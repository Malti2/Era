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

    @State private var spotlightRebuilt = false
    @State private var backupItem: ShareItem?
    @State private var backupError = false
    @State private var showOnboarding = false
    @State private var confirmReset = false
    @State private var resetDone = false

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
                Section("Wiedergabe") {
                    Picker(selection: $defaultRate) {
                        ForEach(AppSettings.rates, id: \.self) { r in
                            Text(r.formatted() + "×").tag(r)
                        }
                    } label: {
                        Label("Standard-Tempo", systemImage: "metronome")
                    }
                    Picker(selection: $skipInterval) {
                        ForEach(AppSettings.skipIntervals, id: \.self) { v in
                            Text("\(v) s").tag(v)
                        }
                    } label: {
                        Label("Sprungweite", systemImage: "goforward.15")
                    }
                    Toggle(isOn: $pauseOnRouteChange) {
                        Label("Bei Kopfhörerabzug pausieren", systemImage: "headphones")
                    }
                    Toggle(isOn: $resumeAfterInterruption) {
                        Label("Nach Anruf fortsetzen", systemImage: "phone.fill")
                    }
                    Toggle(isOn: $haptics) {
                        Label("Haptisches Feedback", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }
                Section("Bibliothek") {
                    LabeledContent("Speicherort", value: "Lokal auf diesem iPhone")
                    LabeledContent("Songs", value: "\(songs.count)")
                    LabeledContent("Versionen", value: "\(versions.count)")
                    LabeledContent("Speicherbedarf", value: LibraryFiles.librarySizeText())
                }
                Section("Backup") {
                    Button {
                        do {
                            backupItem = ShareItem(url: try BackupService.exportURL(store: store))
                        } catch {
                            backupError = true
                        }
                    } label: {
                        Label("Bibliothek exportieren (JSON)", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                Section("Suche & Siri") {
                    Toggle(isOn: $spotlightEnabled) {
                        Label("In Spotlight-Suche zeigen", systemImage: "magnifyingglass")
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
                        Label("Spotlight-Index neu aufbauen", systemImage: spotlightRebuilt ? "checkmark.circle.fill" : "arrow.clockwise")
                    }
                    .disabled(!spotlightEnabled)
                    Label("Siri: „Mit Era abspielen“, „pausieren“, „weiter“", systemImage: "mic.fill")
                }
                Section("Zurücksetzen") {
                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("Alle Daten löschen", systemImage: "trash")
                    }
                }
                Section("Über Era") {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Einführung erneut ansehen", systemImage: "sparkles")
                    }
                    LabeledContent("Datenschutz", value: "Alles lokal, kein Tracking")
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(item: $backupItem) { item in ShareSheet(items: [item.url]) }
            .sheet(isPresented: $showOnboarding) { OnboardingView() }
            .alert("Backup fehlgeschlagen", isPresented: $backupError) {
                Button("OK", role: .cancel) {}
            }
            .confirmationDialog("Era vollständig zurücksetzen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Alle Songs und Daten löschen", role: .destructive) {
                    store.resetEverything()
                    showOnboarding = true
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Songs, Versionen, Playlists, Tags, Packs, Einstellungen und lokale Audiodateien werden dauerhaft gelöscht.")
            }
        }
    }
}

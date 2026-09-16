import SwiftUI
import SwiftData

// Native Einfuehrung beim ersten Start: Willkommen, Datenschutz verstaendlich,
// danach die wichtigsten echten Einstellungen direkt abfragen.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @Query private var songs: [Song]

    @AppStorage(AppSettings.hasOnboardedKey) private var hasOnboarded = false
    @AppStorage(AppSettings.hapticsEnabledKey) private var haptics = true
    @AppStorage(AppSettings.pauseOnRouteChangeKey) private var pauseOnRouteChange = true
    @AppStorage(AppSettings.resumeAfterInterruptionKey) private var resumeAfterInterruption = true
    @AppStorage(AppSettings.spotlightEnabledKey) private var spotlightEnabled = true
    @AppStorage(AppSettings.skipIntervalKey) private var skipInterval = 15
    @AppStorage(AppSettings.defaultRateKey) private var defaultRate = 1.0

    @State private var page = 0

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--era-onboarding-settings") { _page = State(initialValue: 2) }
        else if args.contains("--era-onboarding-privacy") { _page = State(initialValue: 1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                privacyPage.tag(1)
                settingsPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < 2 ? "Weiter" : "Los geht's")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .padding(.top, 8)
        }
        .interactiveDismissDisabled()
    }

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(uiImage: AppIconImage.uiImage)
                .resizable()
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(radius: 12, y: 6)
            Text("Willkommen bei Era")
                .font(.largeTitle.bold())
            Text("Deine eigene Musiksammlung - mit Versionen, Packs und allem, was dazugehört.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text("Deine Musik bleibt bei dir")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 16) {
                privacyRow("iphone", "Lokal gespeichert", "Songs und Daten liegen nur auf diesem iPhone.")
                privacyRow("hand.raised.fill", "Kein Tracking", "Era sammelt keine Nutzungsdaten und analysiert nichts.")
                privacyRow("wifi.slash", "Komplett offline", "Kein Account, keine Cloud, kein Server.")
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    private func privacyRow(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var settingsPage: some View {
        VStack(spacing: 12) {
            Text("Deine Einstellungen")
                .font(.title.bold())
                .padding(.top, 24)
            Text("Alles lässt sich später in den Einstellungen ändern.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Form {
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
                }
                Section {
                    Toggle(isOn: $pauseOnRouteChange) {
                        Label("Bei Kopfhörerabzug pausieren", systemImage: "headphones")
                    }
                    Toggle(isOn: $resumeAfterInterruption) {
                        Label("Nach Anruf fortsetzen", systemImage: "phone.fill")
                    }
                    Toggle(isOn: $haptics) {
                        Label("Haptisches Feedback", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    Toggle(isOn: $spotlightEnabled) {
                        Label("In Spotlight-Suche zeigen", systemImage: "magnifyingglass")
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func finish() {
        hasOnboarded = true
        if spotlightEnabled {
            SpotlightIndexer.reindex(songs: songs)
        } else {
            SpotlightIndexer.clearAll()
        }
        dismiss()
    }
}

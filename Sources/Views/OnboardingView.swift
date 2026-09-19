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
                Text(page < 2 ? "Continue" : "Get Started")
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
            Text("Welcome to Era")
                .font(.largeTitle.bold())
            Text("Your own music collection, with versions, packs, and everything that belongs together.")
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
            Text("Your Music Stays With You")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 16) {
                privacyRow("iphone", "Stored Locally", "Songs and data stay only on this iPhone.")
                privacyRow("hand.raised.fill", "No Tracking", "Era does not collect usage data or analytics.")
                privacyRow("wifi.slash", "Completely Offline", "No account, no cloud, no server.")
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
            Text("Your Settings")
                .font(.title.bold())
                .padding(.top, 24)
            Text("You can change everything later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Form {
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
                }
                Section {
                    Toggle(isOn: $pauseOnRouteChange) {
                        Label("Pause when headphones disconnect", systemImage: "headphones")
                    }
                    Toggle(isOn: $resumeAfterInterruption) {
                        Label("Resume after calls", systemImage: "phone.fill")
                    }
                    Toggle(isOn: $haptics) {
                        Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    Toggle(isOn: $spotlightEnabled) {
                        Label("Show in Spotlight Search", systemImage: "magnifyingglass")
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

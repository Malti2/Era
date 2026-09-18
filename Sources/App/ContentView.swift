import SwiftUI
import SwiftData
import CoreSpotlight

enum AppScreen: String {
    case home, packs, library, search
}

struct ContentView: View {
    @EnvironmentObject private var player: PlayerEngine
    @State private var selection: AppScreen = .home
    @State private var showNowPlaying = false
    @State private var showOnboarding = false
    @State private var showStats = false
    @AppStorage(AppSettings.hasOnboardedKey) private var hasOnboarded = false
    @Environment(\.modelContext) private var modelContext

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--era-library") { _selection = State(initialValue: .library) }
        else if args.contains("--era-packs") { _selection = State(initialValue: .packs) }
        else if args.contains("--era-search") { _selection = State(initialValue: .search) }
        if args.contains("--era-player") { _showNowPlaying = State(initialValue: true) }
        if args.contains("--era-onboarding") { _showOnboarding = State(initialValue: true) }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(String(localized: "Home"), systemImage: "house.fill", value: .home) {
                HomeView(showNowPlaying: $showNowPlaying)
            }
            Tab(String(localized: "Packs"), systemImage: "square.stack.fill", value: .packs) {
                PacksView(showNowPlaying: $showNowPlaying)
            }
            Tab(String(localized: "Library"), systemImage: "music.note.house.fill", value: .library) {
                LibraryView(showNowPlaying: $showNowPlaying)
            }
            Tab(String(localized: "Search"), systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchView(showNowPlaying: $showNowPlaying)
            }
        }
        .eraTabMinimize()
        .modifier(MiniPlayerAccessory(isVisible: player.current != nil && !showNowPlaying, open: { showNowPlaying = true }))
        .sheet(isPresented: $showNowPlaying) { NowPlayingView() }
        .sheet(isPresented: $showStats) { NavigationStack { StatsView() } }
        .onOpenURL { url in
            guard url.scheme == "era" else { return }
            switch url.host {
            case "resume":
                player.resumeOrPlay()
            case "stats":
                showStats = true
            case "song":
                let idString = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let uuid = UUID(uuidString: idString), let song = findSong(uuid), let v = song.primaryVersion {
                    player.play(v, from: song.sortedVersions)
                    showNowPlaying = true
                }
            default:
                break
            }
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let idString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let uuid = UUID(uuidString: idString),
                  let song = findSong(uuid) else { return }
            if let v = song.primaryVersion { player.play(v, from: song.sortedVersions) }
            showNowPlaying = true
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            // Erste Start: Einfuehrung zeigen (Screenshot-Modus ausgenommen)
            if !hasOnboarded && !args.contains("--era-demo") { showOnboarding = true }
            if args.contains("--era-player"), player.current == nil {
                if args.contains("--era-queue") {
                    // Queue-Screenshot: alle Songs als Queue
                    if let songs = try? modelContext.fetch(FetchDescriptor<Song>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])),
                       let first = songs.first, let v = first.primaryVersion {
                        player.play(v, from: songs.compactMap(\.primaryVersion))
                    }
                } else if let first = firstSong(), let v = first.primaryVersion {
                    player.play(v, from: first.sortedVersions)
                }
            }
        }
    }

    private func findSong(_ uuid: UUID) -> Song? {
        var descriptor = FetchDescriptor<Song>()
        return try? modelContext.fetch(descriptor).first { $0.id == uuid }
    }

    private func firstSong() -> Song? {
        var descriptor = FetchDescriptor<Song>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

// Mini-Player ueber der Tab-Leiste: nativ als Bottom-Accessory ab iOS 26.1,
// darunter als eigene Leiste ueber safeAreaInset.
private struct MiniPlayerAccessory: ViewModifier {
    let isVisible: Bool
    let open: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isVisible) {
                MiniPlayer(open: open)
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if isVisible {
                    MiniPlayer(open: open)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
        }
    }
}

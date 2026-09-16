import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class PlayerEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = PlayerEngine()

    @Published var queue: [SongVersion] = []
    @Published var current: SongVersion?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var shuffle = false
    @Published var repeatMode = 0 // 0 aus, 1 alle, 2 einer
    @Published var sleepRemaining: Int?
    @Published var rate: Float = 1.0

    weak var store: EraStore?

    private var audio: AVAudioPlayer?
    private var ticker: Timer?
    private var sleepTimer: Timer?
    private var wasPlayingBeforeInterruption = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    override init() {
        super.init()
        rate = AppSettings.defaultRate
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? AVAudioSession.sharedInstance().setActive(true)
        setupRemoteCommands()
        observeInterruptions()
    }

    // MARK: - Wiedergabe

    func play(_ version: SongVersion, from versions: [SongVersion]) {
        saveResumePosition()
        queue = versions
        current = version
        let url = LibraryFiles.url(for: version)
        #if targetEnvironment(simulator)
        if !FileManager.default.fileExists(atPath: url.path) {
            duration = version.duration
            currentTime = 31
            isPlaying = true
            markPlayed(version)
            startTicker()
            updateNowPlaying()
            return
        }
        #endif
        do {
            audio = try AVAudioPlayer(contentsOf: url)
            audio?.delegate = self
            audio?.enableRate = true
            audio?.rate = rate
            audio?.prepareToPlay()
            audio?.play()
            duration = audio?.duration ?? version.duration
            currentTime = 0
            isPlaying = true
            markPlayed(version)
            startTicker()
            updateNowPlaying()
        } catch {
            isPlaying = false
        }
    }

    // App Intents / Spotlight: weiterhoeren ohne UI-Kontext (Spec 13.4)
    func resumeOrPlay() {
        if current != nil {
            if !isPlaying { toggle() }
            return
        }
        guard let store, let songs = try? store.allSongs(), !songs.isEmpty else { return }
        let recent = songs.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        if let song = recent.first, let v = song.primaryVersion {
            play(v, from: song.sortedVersions)
            if song.resumePosition > 10 { seek(song.resumePosition) }
        }
    }

    private func markPlayed(_ version: SongVersion) {
        guard let song = version.song else { return }
        song.playCount += 1
        song.lastPlayedAt = Date()
        try? song.modelContext?.save()
    }

    private func saveResumePosition() {
        guard let song = current?.song else { return }
        song.resumePosition = currentTime
        try? song.modelContext?.save()
    }

    func toggle() {
        guard current != nil else { return }
        if isPlaying { audio?.pause(); saveResumePosition() } else { audio?.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func seek(_ value: Double) {
        currentTime = value
        audio?.currentTime = value
        updateNowPlaying()
    }

    func skipForward() { seek(min(currentTime + AppSettings.skipInterval, duration)) }
    func skipBackward() { seek(max(currentTime - AppSettings.skipInterval, 0)) }

    func setRate(_ newRate: Float) {
        rate = newRate
        audio?.enableRate = true
        audio?.rate = newRate
        updateNowPlaying()
    }

    // MARK: - Queue

    // Zufaellige Wiedergabe einer Menge (Shuffle-Buttons in Library/Playlists/Packs)
    func playShuffled(_ versions: [SongVersion]) {
        guard !versions.isEmpty else { return }
        shuffle = true
        let mixed = versions.shuffled()
        play(mixed[0], from: mixed)
    }

    func playNext(_ version: SongVersion) {
        if let current, let index = queue.firstIndex(where: { $0.id == current.id }) {
            queue.insert(version, at: index + 1)
        } else {
            play(version, from: [version])
        }
    }

    func playLater(_ version: SongVersion) {
        if current != nil {
            queue.append(version)
        } else {
            play(version, from: [version])
        }
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    func removeFromQueue(at offsets: IndexSet) {
        let removingCurrent = offsets.contains { queue.indices.contains($0) && queue[$0].id == current?.id }
        queue.remove(atOffsets: offsets)
        if removingCurrent { next() }
    }

    func clearQueue() {
        guard let current else { queue = []; return }
        queue = [current]
    }

    func next() { move(1) }
    func previous() { if currentTime > 4 { seek(0) } else { move(-1) } }

    private func move(_ offset: Int) {
        guard !queue.isEmpty, let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        if repeatMode == 2 { play(current, from: queue); return }
        if shuffle {
            var candidates = queue.indices.filter { $0 != index }
            if candidates.isEmpty { candidates = Array(queue.indices) }
            play(queue[candidates.randomElement()!], from: queue)
            return
        }
        var target = index + offset
        if target >= queue.count {
            if repeatMode == 1 { target = 0 } else { seek(0); audio?.pause(); isPlaying = false; saveResumePosition(); updateNowPlaying(); return }
        }
        if target < 0 { target = queue.count - 1 }
        play(queue[target], from: queue)
    }

    func toggleRepeat() { repeatMode = (repeatMode + 1) % 3 }

    // MARK: - Sleep Timer

    func setSleep(minutes: Int) {
        sleepTimer?.invalidate()
        sleepRemaining = minutes * 60
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let r = self.sleepRemaining, r > 1 { self.sleepRemaining = r - 1 }
                else { self.audio?.pause(); self.isPlaying = false; self.sleepRemaining = nil; self.sleepTimer?.invalidate() }
            }
        }
    }
    func cancelSleep() { sleepTimer?.invalidate(); sleepRemaining = nil }

    // MARK: - Ticker

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let a = self.audio { self.currentTime = a.currentTime; self.isPlaying = a.isPlaying }
                else if self.isPlaying { self.currentTime = min(self.currentTime + 0.5, self.duration) }
                self.updateNowPlaying()
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.next() }
    }

    // MARK: - Unterbrechungen (Anruf, Siri) und Route-Wechsel (Kopfhoerer ab)

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleRouteChange(note) }
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying { audio?.pause(); isPlaying = false; updateNowPlaying() }
        case .ended:
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if wasPlayingBeforeInterruption && options.contains(.shouldResume) && AppSettings.bool(AppSettings.resumeAfterInterruptionKey) {
                try? AVAudioSession.sharedInstance().setActive(true)
                audio?.play()
                isPlaying = true
                updateNowPlaying()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        // Kopfhoerer rausgezogen / Bluetooth getrennt: pausieren (Apple-Standardverhalten, abschaltbar)
        if reason == .oldDeviceUnavailable && isPlaying && AppSettings.bool(AppSettings.pauseOnRouteChangeKey) {
            audio?.pause()
            isPlaying = false
            saveResumePosition()
            updateNowPlaying()
        }
    }

    // MARK: - Lockscreen / Kontrollzentrum (Spec 13.1)

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == true { self?.toggle() } }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let version = current else { return }
        let base: [String: Any] = [
            MPMediaItemPropertyTitle: version.displayTitle,
            MPMediaItemPropertyArtist: version.displayArtist,
            MPMediaItemPropertyAlbumTitle: version.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0
        ]
        guard let song = version.song else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = base
            return
        }
        let artFile = version.artworkFile
        let status = song.statusTags.first?.name
        let songID = song.id
        Task {
            var image: UIImage?
            if let artFile, let data = try? Data(contentsOf: LibraryFiles.artworkURL(artFile)) {
                image = UIImage(data: data)
            }
            if image == nil {
                image = DiscArtworkCache.png(for: songID, status: status, size: 512)
            }
            var info = base
            if let image {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}

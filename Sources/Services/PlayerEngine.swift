import Foundation
import AVFoundation
import MediaPlayer
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class PlayerEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = PlayerEngine()

    @Published var queue: [SongVersion] = []
    @Published var current: SongVersion?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var shuffle = false
    @Published var repeatMode = 0 // 0 off, 1 all, 2 one
    @Published var sleepRemaining: Int?
    @Published var rate: Float = 1.0

    weak var store: EraStore?

    private var audio: AVAudioPlayer?
    private var nextAudio: AVAudioPlayer?
    private var nextVersion: SongVersion?
    private var transitionArmed = false
    private var fading = false
    private var fadeWindow: Double = 1
    private var crackle: AVAudioPlayer?
    private var ticker: Timer?
    private var sleepTimer: Timer?
    private var wasPlayingBeforeInterruption = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    #if canImport(ActivityKit)
    private var nowPlayingActivity: Activity<EraActivityAttributes>?
    #endif

    override init() {
        super.init()
        rate = AppSettings.defaultRate
        configureAudioSession()
        setupRemoteCommands()
        observeInterruptions()
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDidBecomeActive() }
        }
    }

    // Playback category + active session: the app keeps running in the
    // background (UIBackgroundModes audio) and audio survives minimising.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func handleDidBecomeActive() {
        configureAudioSession()
        // Defensive: if the system paused us while backgrounded, resume cleanly.
        if isPlaying, let a = audio, !a.isPlaying {
            a.play()
        }
    }

    // MARK: - Playback

    func play(_ version: SongVersion, from versions: [SongVersion]) {
        cancelTransition()
        recordPlayEvent(finished: false)
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
            configureAudioSession()
            audio = try AVAudioPlayer(contentsOf: url)
            audio?.delegate = self
            audio?.enableRate = true
            audio?.rate = rate
            audio?.volume = 1
            audio?.prepareToPlay()
            audio?.play()
            duration = audio?.duration ?? version.duration
            currentTime = 0
            isPlaying = true
            markPlayed(version)
            startTicker()
            updateNowPlaying()
            prepareNext()
        } catch {
            isPlaying = false
        }
    }

    // App Intents / Spotlight / widget deep link: resume without UI context.
    func resumeOrPlay() {
        if current != nil {
            if !isPlaying {
                configureAudioSession()
                toggle()
            }
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
        updateSharedRecent()
    }

    private func recordPlayEvent(finished: Bool) {
        guard let version = current, let song = version.song else { return }
        let seconds = finished ? duration : min(currentTime, duration)
        guard seconds >= 5 else { return }
        let event = PlayEvent(date: Date(), seconds: seconds, songID: song.id,
                              title: version.displayTitle, artist: version.displayArtist)
        song.modelContext?.insert(event)
        try? song.modelContext?.save()
    }

    private func saveResumePosition() {
        guard let song = current?.song else { return }
        song.resumePosition = currentTime
        try? song.modelContext?.save()
    }

    func toggle() {
        guard current != nil else { return }
        if isPlaying {
            cancelTransition()
            audio?.pause()
            saveResumePosition()
        } else {
            configureAudioSession()
            audio?.play()
            prepareNext()
        }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func seek(_ value: Double) {
        cancelTransition()
        currentTime = value
        audio?.currentTime = value
        prepareNext()
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

    // MARK: - Gapless / Crossfade

    // Linear successor used for preloading. Shuffle picks at switch time, so
    // there is nothing reliable to preload there.
    private func linearSuccessor() -> SongVersion? {
        guard !queue.isEmpty, let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return nil }
        if repeatMode == 2 { return current }
        if shuffle { return nil }
        let target = index + 1
        if target < queue.count { return queue[target] }
        if repeatMode == 1 { return queue.first }
        return nil
    }

    private func prepareNext() {
        guard nextAudio == nil, AppSettings.transitionStyle != .off,
              let next = linearSuccessor(), next.id != current?.id || repeatMode == 2 else { return }
        let url = LibraryFiles.url(for: next)
        guard FileManager.default.fileExists(atPath: url.path),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.enableRate = true
        player.rate = rate
        player.prepareToPlay()
        nextAudio = player
        nextVersion = next
    }

    private func cancelTransition() {
        transitionArmed = false
        fading = false
        audio?.volume = 1
        nextAudio?.stop()
        nextAudio = nil
        nextVersion = nil
    }

    private func checkTransition() {
        guard isPlaying, let a = audio else { return }
        if !transitionArmed && nextAudio == nil { prepareNext() }
        guard let nextA = nextAudio, let next = nextVersion, a.duration > 1 else { return }
        let remaining = a.duration - a.currentTime
        switch AppSettings.transitionStyle {
        case .off:
            return
        case .gapless:
            if !transitionArmed && remaining <= 0.35 {
                nextA.volume = 1
                nextA.play(atTime: nextA.deviceCurrentTime + max(remaining, 0.01))
                transitionArmed = true
            }
        case .crossfade:
            let window = min(AppSettings.crossfadeSeconds, a.duration - 1)
            guard window >= 2 else { return }
            if !transitionArmed && remaining <= window {
                nextA.volume = 0
                nextA.play()
                fadeWindow = max(remaining, 0.2)
                transitionArmed = true
                fading = true
            }
            if fading {
                let progress = min(max(1 - remaining / fadeWindow, 0), 1)
                a.volume = Float(1 - progress)
                nextA.volume = Float(progress)
            }
        }
        _ = next
    }

    // Handoff after a scheduled gapless/crossfade transition: the next player
    // is already running and takes over as the current track.
    private func finishTransition(from old: AVAudioPlayer) {
        guard let nextA = nextAudio, let next = nextVersion else { return }
        old.delegate = nil
        old.stop()
        old.volume = 1
        audio = nextA
        nextAudio = nil
        nextVersion = nil
        transitionArmed = false
        fading = false
        recordPlayEvent(finished: true)
        current = next
        duration = nextA.duration
        currentTime = 0
        isPlaying = true
        markPlayed(next)
        updateNowPlaying()
        prepareNext()
    }

    // MARK: - Vinyl crackle

    private func syncCrackle() {
        let enabled = AppSettings.bool(AppSettings.crackleEnabledKey, default: false)
        if enabled, isPlaying, current != nil {
            if crackle == nil, let url = Bundle.main.url(forResource: "vinyl-crackle", withExtension: "wav") {
                crackle = try? AVAudioPlayer(contentsOf: url)
                crackle?.numberOfLoops = -1
                crackle?.prepareToPlay()
            }
            crackle?.volume = Float(AppSettings.crackleVolume)
            crackle?.play()
        } else {
            crackle?.pause()
        }
    }

    // MARK: - Queue

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
        cancelTransition()
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
            if repeatMode == 1 { target = 0 } else {
                seek(0)
                audio?.pause()
                isPlaying = false
                saveResumePosition()
                updateNowPlaying()
                return
            }
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
                else {
                    self.cancelTransition()
                    self.audio?.pause()
                    self.isPlaying = false
                    self.sleepRemaining = nil
                    self.sleepTimer?.invalidate()
                }
            }
        }
    }
    func cancelSleep() { sleepTimer?.invalidate(); sleepRemaining = nil }

    // MARK: - Ticker

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let a = self.audio {
                    self.currentTime = a.currentTime
                    self.isPlaying = a.isPlaying
                    self.checkTransition()
                } else if self.isPlaying {
                    self.currentTime = min(self.currentTime + 0.25, self.duration)
                }
                self.syncCrackle()
                self.updateNowPlaying()
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if player === self.audio {
                if self.transitionArmed {
                    self.finishTransition(from: player)
                } else {
                    self.recordPlayEvent(finished: true)
                    self.next()
                }
            }
        }
    }

    // MARK: - Interruptions (calls, Siri) and route changes (headphones out)

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
            if isPlaying {
                cancelTransition()
                audio?.pause()
                isPlaying = false
                updateNowPlaying()
            }
        case .ended:
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if wasPlayingBeforeInterruption && options.contains(.shouldResume) && AppSettings.bool(AppSettings.resumeAfterInterruptionKey) {
                try? AVAudioSession.sharedInstance().setActive(true)
                audio?.play()
                isPlaying = true
                prepareNext()
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
        // Headphones unplugged / Bluetooth dropped: pause (Apple default, optional)
        if reason == .oldDeviceUnavailable && isPlaying && AppSettings.bool(AppSettings.pauseOnRouteChangeKey) {
            cancelTransition()
            audio?.pause()
            isPlaying = false
            saveResumePosition()
            updateNowPlaying()
        }
    }

    // MARK: - Lock screen / Control Center (Spec 13.1)

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in
            guard let self else { return }
            if !self.isPlaying {
                try? AVAudioSession.sharedInstance().setActive(true)
                if self.current != nil { self.toggle() } else { self.resumeOrPlay() }
            }
        }; return .success }
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
        syncLiveActivity()
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

    // MARK: - Live Activity

    private var activityLastSync: (id: UUID, playing: Bool, position: Double)?

    private func syncLiveActivity() {
        #if canImport(ActivityKit)
        guard let version = current else {
            activityLastSync = nil
            let activity = nowPlayingActivity
            nowPlayingActivity = nil
            if let activity {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        // Throttle: full updates on track/play-state change and on seeks,
        // not every ticker step. Progress animates on-device via timerInterval.
        let positionBucket = (currentTime / 2).rounded() * 2
        let snapshot = (id: version.id, playing: isPlaying, position: positionBucket)
        if let last = activityLastSync, last.id == snapshot.id,
           last.playing == snapshot.playing, last.position == snapshot.position { return }
        activityLastSync = snapshot
        let songID = version.song?.id ?? version.id
        let state = EraActivityAttributes.ContentState(
            songID: songID,
            title: version.displayTitle,
            artist: version.displayArtist,
            duration: duration,
            position: currentTime,
            referenceDate: Date(),
            rate: rate,
            isPlaying: isPlaying
        )
        Task {
            if let activity = nowPlayingActivity {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            } else {
                guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
                nowPlayingActivity = try? Activity.request(
                    attributes: EraActivityAttributes(name: "Era"),
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            }
        }
        #endif
    }

    // MARK: - Home Screen widget data (App Group)

    private func updateSharedRecent() {
        guard let store, let songs = try? store.allSongs() else { return }
        let recent = songs.filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            .prefix(5)
        var tracks: [EraShared.RecentTrack] = []
        for song in recent {
            var artName: String?
            if let version = song.primaryVersion {
                var data: Data?
                if let file = version.artworkFile {
                    data = try? Data(contentsOf: LibraryFiles.artworkURL(file))
                }
                if data == nil {
                    data = DiscArtworkCache.png(for: song.id, status: song.statusTags.first?.name, size: 300).pngData()
                }
                if let data {
                    let name = "\(song.id.uuidString).png"
                    EraShared.copyArtwork(data: data, name: name)
                    artName = name
                }
            }
            tracks.append(EraShared.RecentTrack(id: song.id, title: song.title, artist: song.displayArtist, artwork: artName))
        }
        EraShared.writeRecent(tracks)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

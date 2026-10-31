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
    @Published var shuffle = false {
        didSet { if shuffle && !oldValue { shuffleBag.reset(startingWith: current?.id) } }
    }
    @Published var repeatMode = 0 // 0 off, 1 all, 2 one
    @Published private(set) var sleepTimer = SleepTimerState()
    @Published private(set) var loop = ABLoop()
    @Published var rate: Float = 1.0
    /// Set when a track could not be loaded (missing/unreadable file); the UI shows it briefly.
    @Published var playbackError: String?

    var sleepRemaining: Int? { sleepTimer.remaining }

    weak var store: EraStore?

    private var audio: AVAudioPlayer?
    private var nextAudio: AVAudioPlayer?
    private var nextVersion: SongVersion?
    private var transitionArmed = false
    private var fading = false
    private var fadeWindow: Double = 1
    private var crackle: AVAudioPlayer?
    private var ticker: Timer?
    private var sleepTicker: Timer?
    private var shuffleBag = ShuffleBag()
    private var wasPlayingBeforeInterruption = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

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

    /// Starts a version. Returns false when the audio file could not be loaded; the queue
    /// then still points at it so `next()` can move on.
    @discardableResult
    func play(_ version: SongVersion, from versions: [SongVersion]) -> Bool {
        cancelTransition()
        loop.clear()
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
            return true
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
            playbackError = nil
            startTicker()
            updateNowPlaying()
            prepareNext()
            persistSession()
            return true
        } catch {
            audio?.stop()
            audio = nil
            isPlaying = false
            currentTime = 0
            duration = version.duration
            playbackError = String(localized: "“\(version.displayTitle)” can’t be played: its audio file is missing or unreadable.")
            updateNowPlaying()
            persistSession()
            return false
        }
    }

    // MARK: - Session (queue survives app restarts)

    func persistSession() {
        guard let current else { return }
        PlaybackSnapshot(queue: queue.map(\.id), current: current.id, position: currentTime, shuffle: shuffle, repeatMode: repeatMode).save()
    }

    /// Puts the last queue back (paused) so the mini player is there after a relaunch.
    func restoreSession() {
        guard current == nil, let store, let snapshot = PlaybackSnapshot.load(),
              let versions = try? store.allVersions() else { return }
        let byID = Dictionary(versions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let restored = snapshot.restored(available: Set(byID.keys), durations: byID.mapValues(\.duration)),
              let version = byID[restored.current] else { return }
        queue = restored.queue.compactMap { byID[$0] }
        current = version
        repeatMode = snapshot.repeatMode
        shuffle = snapshot.shuffle
        if let loaded = try? AVAudioPlayer(contentsOf: LibraryFiles.url(for: version)) {
            loaded.delegate = self
            loaded.enableRate = true
            loaded.rate = rate
            loaded.prepareToPlay()
            loaded.currentTime = restored.position
            audio = loaded
            duration = loaded.duration
        } else {
            duration = version.duration
        }
        currentTime = restored.position
        isPlaying = false
        startTicker()
        updateNowPlaying()
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
            play(v, from: [v])
            if song.resumePosition > 10 { seek(song.resumePosition) }
        }
    }

    private func markPlayed(_ version: SongVersion) {
        guard let song = version.song else { return }
        song.playCount += 1
        song.lastPlayedAt = Date()
        try? song.modelContext?.save()
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
            // Nothing loaded (failed load or file missing): start the track from scratch.
            if audio == nil, let current { play(current, from: queue); return }
            configureAudioSession()
            audio?.play()
            prepareNext()
        }
        isPlaying.toggle()
        updateNowPlaying()
        persistSession()
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
        guard nextAudio == nil, AppSettings.transitionStyle != .off, !sleepTimer.stopsAtTrackEnd,
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
        guard isPlaying, let a = audio, !sleepTimer.stopsAtTrackEnd, !loop.isActive else { return }
        if let left = sleepTimer.remaining, left <= SleepTimerState.fadeSeconds + 1 { return }
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
        shuffleBag.reset(startingWith: mixed[0].id)
        play(mixed[0], from: mixed)
    }

    // Version switch while playing: replaces every version of the same song
    // in the queue with the chosen one, so a song never occupies more than
    // one queue slot regardless of how many versions it has.
    func switchVersion(_ version: SongVersion) {
        guard let song = version.song else { play(version, from: [version]); return }
        let ids = Set(song.versions.map(\.id))
        let anchor = queue.firstIndex(where: { $0.id == current?.id }) ?? queue.count
        var newQueue = queue.filter { !ids.contains($0.id) }
        newQueue.insert(version, at: min(anchor, newQueue.count))
        // Comparing versions of one song keeps the loop, so A/B listening lines up.
        let keptLoop = loop
        play(version, from: newQueue)
        loop = keptLoop
    }

    /// Cycles the A-B loop: mark start, mark end, clear.
    func cycleLoop() {
        loop.advance(at: currentTime, duration: duration)
    }

    func clearLoop() { loop.clear() }

    // MARK: Marker

    /// Marker der laufenden Version (SwiftData ist observable, die Views aktualisieren sich von selbst).
    var markers: [VersionMarker] { current?.markers ?? [] }

    /// Setzt einen Marker an der aktuellen Position. Gibt ihn zurueck (auch wenn dort schon einer lag).
    @discardableResult
    func addMarkerHere() -> VersionMarker? {
        guard let current, let store else { return nil }
        return store.addMarker(at: currentTime, to: current)
    }

    func nextMarker() {
        guard let marker = VersionMarkers.next(after: currentTime, in: markers) else { return }
        seek(marker.time)
    }

    func previousMarker() {
        guard let marker = VersionMarkers.previous(before: currentTime, in: markers) else { return }
        seek(marker.time)
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

    private func move(_ offset: Int, skipped: Int = 0) {
        cancelTransition()
        guard !queue.isEmpty, let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        if repeatMode == 2 { play(current, from: queue); return }
        var target: Int
        if shuffle {
            if offset < 0 {
                guard let previousID = shuffleBag.previous(current: current.id),
                      let previous = queue.first(where: { $0.id == previousID }) else { seek(0); return }
                play(previous, from: queue)
                return
            }
            guard let nextID = shuffleBag.next(in: queue.map(\.id), current: current.id, wrap: repeatMode == 1),
                  let nextIndex = queue.firstIndex(where: { $0.id == nextID }) else { endOfQueue(); return }
            target = nextIndex
        } else {
            target = index + offset
            if target >= queue.count {
                guard repeatMode == 1 else { endOfQueue(); return }
                target = 0
            }
            if target < 0 { target = queue.count - 1 }
        }
        // A track whose file is gone is skipped instead of stalling the queue.
        if !play(queue[target], from: queue), skipped < queue.count - 1 { move(offset, skipped: skipped + 1) }
    }

    private func endOfQueue() {
        seek(0)
        audio?.pause()
        isPlaying = false
        saveResumePosition()
        updateNowPlaying()
        persistSession()
    }

    func toggleRepeat() { repeatMode = (repeatMode + 1) % 3 }

    // MARK: - Sleep Timer

    func setSleep(minutes: Int) {
        sleepTimer.start(minutes: minutes)
        sleepTicker?.invalidate()
        guard sleepTimer.isActive else { return }
        sleepTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleSleepTick() }
        }
    }

    /// Stops after the current track instead of after a fixed time.
    func setSleepAtEndOfTrack() {
        sleepTicker?.invalidate()
        sleepTimer.startEndOfTrack()
        cancelTransition()
    }

    func cancelSleep() {
        sleepTicker?.invalidate()
        sleepTimer.cancel()
        audio?.volume = 1
    }

    private func handleSleepTick() {
        switch sleepTimer.tick() {
        case .none:
            break
        case .fade(let volume):
            audio?.volume = volume
        case .expired:
            sleepTicker?.invalidate()
            cancelTransition()
            audio?.pause()
            audio?.volume = 1
            isPlaying = false
            saveResumePosition()
            updateNowPlaying()
            persistSession()
        }
    }

    // MARK: - Ticker

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let a = self.audio {
                    if let target = self.loop.jumpTarget(for: a.currentTime) {
                        a.currentTime = target
                    }
                    self.currentTime = a.currentTime
                    self.isPlaying = a.isPlaying
                    self.checkTransition()
                } else if self.isPlaying {
                    self.currentTime = min(self.currentTime + 0.25, self.duration)
                }
                self.syncCrackle()
                self.updateElapsedPlaybackTime()
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
                    if self.sleepTimer.trackFinished() {
                        self.isPlaying = false
                        self.currentTime = 0
                        self.audio?.currentTime = 0
                        self.updateNowPlaying()
                        self.persistSession()
                    } else {
                        self.next()
                    }
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

    // Cheap lock-screen progress refresh for the 0.25s ticker: mutates the
    // existing Now Playing entry in place instead of rebuilding it (artwork
    // load included) four times a second. Full updateNowPlaying() runs on
    // track, play-state, rate and seek changes only.
    private func updateElapsedPlaybackTime() {
        guard current != nil, var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

}

import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// 播放内核：一个 AVPlayer + 队列 + 单曲解析。
/// 只有「当前曲目变化」才会去解析播放地址，避免每帧都打接口。
@MainActor
final class PlayerEngine: ObservableObject {
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = -1
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var lyrics: LyricsDoc = .empty
    @Published private(set) var isLoadingLyrics = false
    /// 没取到歌词时的原因（给空态展示，方便判断是接口问题还是曲目本身没有）。
    @Published private(set) var lyricsNote = ""
    @Published private(set) var isFavorite = false
    @Published private(set) var actualQuality: String = "unknown"
    @Published var mode: PlayMode = .sequential {
        didSet {
            persistQueueSoon()
            if mode != oldValue { persistMode?() }
        }
    }
    /// 由外部（设置页）灌入，切歌时读取。
    var quality: Quality = .standard
    var syncHistory: Bool = true
    /// 播放模式变化时回报给设置层落盘。
    var persistMode: (() -> Void)?

    var current: Track? {
        guard index >= 0, index < queue.count else { return nil }
        return queue[index]
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var loadGeneration = 0
    private var lyricsGeneration = 0
    private var pendingSeek: Double?
    private var shuffleHistory: [Int] = []
    private var listenedSeconds: Double = 0
    private var hasReported = false
    private var tickCount = 0
    private var lastTickSeconds: Double = 0
    private var cachedArtwork: (url: String, artwork: MPMediaItemArtwork)?
    private var persistTask: Task<Void, Never>?
    private let queueStorageKey = "saved-queue-v1"

    init() {
        configureAudioSession()
        player.automaticallyWaitsToMinimizeStalling = true
        addTimeObserver()
        addNotifications()
        setupRemoteCommands()
    }

    // MARK: - 生命周期

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func addTimeObserver() {
        // 0.5 秒一次：歌词高亮够用，界面重绘频率减半。
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.handleTick(seconds: time.seconds)
            }
        }
    }

    private func addNotifications() {
        let center = NotificationCenter.default
        endObserver = center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded() }
        }
        failObserver = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isBuffering = false
                self.isPlaying = false
                self.errorMessage = "这首歌暂时没能播放，稍后可以再点一次。"
            }
        }
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                guard let self, raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                self.isPlaying = false
                self.updateNowPlaying()
            }
        }
    }

    @Published var errorMessage: String?

    // MARK: - 队列

    func play(_ tracks: [Track], startIndex: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        index = min(max(0, startIndex), tracks.count - 1)
        shuffleHistory.removeAll()
        loadCurrent(autoplay: true, seekTo: nil)
    }

    /// 启动时恢复上次队列：定位到那一首与那个进度，但不自动出声。
    func restoreQueue() {
        guard queue.isEmpty,
              let data = UserDefaults.standard.data(forKey: queueStorageKey),
              let saved = try? JSONDecoder().decode(SavedQueue.self, from: data),
              !saved.tracks.isEmpty
        else { return }
        queue = saved.tracks
        index = min(max(0, saved.index), saved.tracks.count - 1)
        position = saved.positionSeconds
        loadCurrent(autoplay: false, seekTo: saved.positionSeconds)
    }

    /// 下一首播放：插到当前曲目后面，不打乱正在播的那首。
    func enqueueNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard !queue.isEmpty, index >= 0 else {
            play(tracks, startIndex: 0)
            return
        }
        let head = Array(queue.prefix(index + 1))
        let tail = Array(queue.suffix(from: index + 1))
        queue = head + tracks + tail
        persistQueueSoon()
    }

    /// 添加到队列末尾。
    func enqueueLast(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard !queue.isEmpty, index >= 0 else {
            play(tracks, startIndex: 0)
            return
        }
        queue.append(contentsOf: tracks)
        persistQueueSoon()
    }

    func jump(to position: Int) {
        guard position >= 0, position < queue.count, position != index else { return }
        index = position
        loadCurrent(autoplay: true, seekTo: nil)
    }

    func remove(at position: Int) {
        guard position >= 0, position < queue.count else { return }
        let playing = index
        queue.remove(at: position)
        if queue.isEmpty {
            index = -1
            player.pause()
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            isBuffering = false
            self.position = 0
            duration = 0
            lyrics = .empty
            lyricsNote = ""
            updateNowPlaying()
            persistQueueSoon()
            return
        }
        if position == playing {
            index = min(playing, queue.count - 1)
            loadCurrent(autoplay: isPlaying, seekTo: nil)
        } else if position < playing {
            index = playing - 1
        }
        persistQueueSoon()
    }

    /// 清空待播：只留正在播的这一首。
    func clearUpcoming() {
        guard index >= 0, index + 1 < queue.count else { return }
        queue = Array(queue.prefix(index + 1))
        persistQueueSoon()
    }

    // MARK: - 传输控制

    func togglePlayPause() {
        guard player.currentItem != nil else {
            if let current, let start = queue.firstIndex(of: current) {
                index = start
                loadCurrent(autoplay: true, seekTo: nil)
            }
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            ensureAudioSessionActive()
        }
        updateNowPlaying()
    }

    func resume() {
        guard player.currentItem != nil else { return }
        player.play()
        isPlaying = true
        ensureAudioSessionActive()
        updateNowPlaying()
    }

    func next(auto: Bool = false) {
        guard !queue.isEmpty else { return }
        if auto, mode == .one {
            loadCurrent(autoplay: true, seekTo: 0)
            return
        }
        if mode == .shuffle, queue.count > 1 {
            shuffleHistory.append(index)
            if shuffleHistory.count > 200 { shuffleHistory.removeFirst() }
            var target = index
            while target == index {
                target = Int.random(in: 0..<queue.count)
            }
            index = target
            loadCurrent(autoplay: true, seekTo: nil)
            return
        }
        if index + 1 < queue.count {
            index += 1
            loadCurrent(autoplay: true, seekTo: nil)
            return
        }
        if mode == .all {
            index = 0
            loadCurrent(autoplay: true, seekTo: nil)
            return
        }
        player.pause()
        isPlaying = false
        seek(to: 0)
    }

    func previous() {
        if position > 4 {
            seek(to: 0)
            return
        }
        if mode == .shuffle, let last = shuffleHistory.popLast() {
            index = last
            loadCurrent(autoplay: true, seekTo: nil)
            return
        }
        index = max(0, index - 1)
        loadCurrent(autoplay: true, seekTo: nil)
    }

    func seek(to seconds: Double) {
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        position = target
        updateNowPlaying()
        persistQueueSoon()
    }

    func cycleMode() {
        mode = mode.next
    }

    func toggleFavorite() {
        guard let track = current else { return }
        let target = !isFavorite
        isFavorite = target
        Task {
            do {
                _ = try await MusicAPI.shared.setFavorite(track.id, favorite: target)
            } catch {
                isFavorite = !target
                errorMessage = target ? "收藏没有成功，请稍后再试。" : "取消收藏没有成功，请稍后再试。"
            }
        }
    }

    func clear() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        index = -1
        isPlaying = false
        isBuffering = false
        position = 0
        duration = 0
        lyrics = .empty
        lyricsNote = ""
        isFavorite = false
        updateNowPlaying()
        UserDefaults.standard.removeObject(forKey: queueStorageKey)
    }

    // MARK: - 歌词

    private func loadLyrics(for track: Track) {
        lyricsGeneration += 1
        let mine = lyricsGeneration
        isLoadingLyrics = true
        lyricsNote = ""
        Task {
            let document = await LyricsService.load(track: track)
            guard mine == lyricsGeneration else { return }
            isLoadingLyrics = false
            lyrics = document
            if lyrics.lines.isEmpty { lyricsNote = LyricsService.lastDiagnostic }
        }
    }

    /// 空态里的「重新加载」：先丢掉这首歌的歌词缓存，再拉一次。
    func reloadLyrics() {
        guard let track = current else { return }
        LyricsService.forget(track.id)
        loadLyrics(for: track)
    }

    // MARK: - 单曲解析

    private func loadCurrent(autoplay: Bool, seekTo: Double?) {
        guard let track = current else { return }
        loadGeneration += 1
        let generation = loadGeneration
        listenedSeconds = 0
        hasReported = false
        lastTickSeconds = 0
        lyrics = .empty
        isFavorite = false
        isBuffering = true
        position = seekTo ?? 0
        duration = track.durationSeconds ?? 0
        pendingSeek = seekTo
        updateNowPlaying()

        Task {
            do {
                let info = try await MusicAPI.shared.resolvePlayback(trackId: track.id, quality: quality)
                guard generation == loadGeneration else { return }
                apply(info, autoplay: autoplay)
            } catch {
                guard generation == loadGeneration else { return }
                isBuffering = false
                isPlaying = false
                if let apiError = error as? APIError, apiError.isAuthFailure {
                    errorMessage = SessionBridge.isAuthenticated
                        ? "登录状态已失效，请重新登录。"
                        : "播放需要先登录华为账号。"
                } else {
                    errorMessage = error.readableMessage
                }
            }
        }

        loadLyrics(for: track)

        Task {
            let favorite = (try? await MusicAPI.shared.favoriteExist(track.id)) ?? false
            guard generation == loadGeneration else { return }
            isFavorite = favorite
        }
    }

    private func apply(_ info: PlaybackInfo, autoplay: Bool) {
        actualQuality = info.actualQuality
        let item = AVPlayerItem(url: info.url)
        player.replaceCurrentItem(with: item)
        if let songDuration = info.durationSeconds, songDuration > 0 {
            duration = songDuration
        }
        if let target = pendingSeek, target > 0 {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            position = target
        } else {
            position = 0
        }
        pendingSeek = nil
        if autoplay {
            ensureAudioSessionActive()
            player.play()
            isPlaying = true
        } else {
            isPlaying = false
            isBuffering = false
        }
        updateNowPlaying()
        persistQueueSoon()
    }

    private func ensureAudioSessionActive() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - 进度与上报

    private func handleTick(seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        let delta = seconds - lastTickSeconds
        lastTickSeconds = seconds

        // 位置只在真的变化时推送，避免定时器空转让整棵树重绘。
        if abs(position - seconds) >= 0.05 {
            position = seconds
        }
        if duration <= 0, let itemDuration = player.currentItem?.duration.seconds,
           itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
        let rate = player.rate
        if isPlaying, rate == 0 {
            if !isBuffering { isBuffering = true }
        } else if rate > 0, isBuffering {
            isBuffering = false
        }
        if rate > 0, !hasReported {
            // 用真实时间差累加：拖动进度会拿到负值，卡顿时也不会多算。
            listenedSeconds += max(0, min(delta, 2))
            maybeReportPlayback()
        }
        tickCount += 1
        // 锁屏信息不必每两秒重写一次：MPNowPlayingInfoCenter 每次写入都会触发系统侧刷新。
        if tickCount % 10 == 0 { updateNowPlaying() }
        if tickCount % 40 == 0 { persistQueueSoon() }
    }

    private func maybeReportPlayback() {
        guard syncHistory, !hasReported, let track = current else { return }
        let threshold = duration > 0 ? min(30, duration * 0.5) : 30
        guard listenedSeconds >= threshold else { return }
        hasReported = true
        let listened = listenedSeconds
        Task {
            try? await MusicAPI.shared.reportPlayback(track: track, listenedSeconds: listened)
        }
    }

    private func handleTrackEnded() {
        next(auto: true)
    }

    // MARK: - 落盘

    private func persistQueueSoon() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.persistQueue()
        }
    }

    private func persistQueue() {
        guard !queue.isEmpty else {
            UserDefaults.standard.removeObject(forKey: queueStorageKey)
            return
        }
        let saved = SavedQueue(tracks: queue, index: index, positionSeconds: position)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: queueStorageKey)
        }
    }

    // MARK: - 锁屏 / 控制中心

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        _ = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        _ = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.player.pause()
                self?.isPlaying = false
                self?.updateNowPlaying()
            }
            return .success
        }
        _ = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        _ = center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        _ = center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        _ = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let target = positionEvent.positionTime
            Task { @MainActor in self?.seek(to: target) }
            return .success
        }
    }

    /// 锁屏封面对象只建一次：每 5 秒重建 MPMediaItemArtwork 会白白触发系统侧刷新。
    private func nowPlayingArtwork(for cover: String) -> MPMediaItemArtwork? {
        if let cached = cachedArtwork, cached.url == cover { return cached.artwork }
        guard let image = CoverCache.shared.cached(cover) else { return nil }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        cachedArtwork = (cover, artwork)
        return artwork
    }

    private func updateNowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistLine,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let album = track.album?.title {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let cover = track.coverUrl, let art = nowPlayingArtwork(for: cover) {
            info[MPMediaItemPropertyArtwork] = art
        } else if let cover = track.coverUrl {
            CoverCache.shared.load(cover) { [weak self] image in
                guard let image else { return }
                Task { @MainActor in
                    guard let self, self.current?.coverUrl == cover else { return }
                    var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                }
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

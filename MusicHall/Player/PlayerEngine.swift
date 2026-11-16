import AVFoundation
import Combine
import MediaPlayer
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// 只有播放进度。单独成对象，是为了让「每秒两次」的更新不影响其它视图。
@MainActor
final class PlaybackClock: ObservableObject {
    @Published private(set) var position: Double = 0

    /// 上一次与播放器对齐的时刻。
    private var stamp = Date()
    /// 是否真的在走（暂停/缓冲时为 false，外推会停住）。
    private var running = false

    /// 定位或换曲：位置立刻改，但不算「正在走」。
    func set(_ seconds: Double) {
        position = seconds
        stamp = Date()
    }

    /// 播放器 2Hz 回调：校准基准时刻，顺带更新是否在走的判断。
    func sync(_ seconds: Double, running isRunning: Bool) {
        running = isRunning
        stamp = Date()
        if abs(position - seconds) >= 0.05 {
            position = seconds
        }
    }

    func freeze() {
        running = false
        stamp = Date()
    }

    func resume() {
        running = true
        stamp = Date()
    }

    /// 把 2Hz 的进度按「距上次校准过了多久」外推成连续值。
    ///
    /// 这是歌词能平滑走词的关键：只读 `position` 的话，进度每 0.5 秒才跳一次，
    /// 无论界面刷多快，看上去都是「一顿一顿」的。
    func live(now: Date = .now) -> Double {
        guard running else { return position }
        let drift = now.timeIntervalSince(stamp)
        // 只补到下个回调之前：补太多就成了「提前」，歌词会跑到声音前面去。
        return position + min(max(drift, 0), 0.3)
    }
}

/// 音频从解码到真正出声有一段固定延迟，而媒体时间不含这段。
/// 直接用媒体时间算歌词，看到的永远比听到的早一点点——这里统一补回来。
enum LyricTiming {
    static let outputLatency: Double = 0.15
}

/// 播放内核：一个 AVPlayer + 队列 + 单曲解析。
/// 只有「当前曲目变化」才会去解析播放地址，避免每帧都打接口。
@MainActor
final class PlayerEngine: ObservableObject {
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = -1
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    /// 播放进度单独一个发布源：2Hz 的更新只惊动进度条、歌词这几个小视图，
    /// 不会带着玻璃层、列表、Tab 栏一起重绘（那是「整个软件卡卡的」的主因）。
    let clock = PlaybackClock()
    var position: Double { clock.position }
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
    /// 用户在设置里微调的歌词偏移（秒）。正值表示把歌词往后推。
    var lyricOffset: Double = 0
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
    /// 退到后台就把进度写盘：被系统或用户杀掉时最多只丢几秒。
    private var resignObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var loadGeneration = 0
    private var lyricsGeneration = 0
    private var pendingSeek: Double?
    /// seek 发起的时刻与重试次数：用来判断「目标位置到底落下去没有」。
    private var seekIssuedAt: Date?
    private var seekRetries = 0
    /// 一次只允许一个 seek 在路上：KVO、兜底计时器和「按播放」都会来叫它。
    private var seekInFlight = false
    /// 监听 item 是否就绪：只有 readyToPlay 之后的 seek 才会被真正执行。
    private var itemStatusObservation: NSKeyValueObservation?
    private var shuffleHistory: [Int] = []
    private var listenedSeconds: Double = 0
    private var hasReported = false
    private var tickCount = 0
    private var lastTickSeconds: Double = 0
    private var cachedArtwork: (url: String, artwork: MPMediaItemArtwork)?
    /// 锁屏 / 通知中心的歌词卡片。系统的播控组件只画固定的那几个字段，
    /// 歌词只能用 Live Activity 送出去（见 Shared/LyricsActivityAttributes.swift）。
    @available(iOS 16.1, *)
    private var lyricsActivity: Activity<LyricsActivityAttributes>?
    /// 上次下发给卡片的那一句和播放状态：只在这两个变了的时候才更新。
    private var activityLine = -1
    private var activityPlaying = false
    private var persistTask: Task<Void, Never>?
    private let queueStorageKey = "saved-queue-v1"

    init() {
        configureAudioSession()
        player.automaticallyWaitsToMinimizeStalling = true
        addTimeObserver()
        addNotifications()
        setupRemoteCommands()
        // 进程被杀掉时 Live Activity 可能还挂在锁屏上，启动先清掉。
        if #available(iOS 16.2, *) {
            Task { @MainActor in
                for activity in Activity<LyricsActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    // MARK: - 生命周期

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func addTimeObserver() {
        // 0.25 秒一次：歌词的时间轴越密，外推要补的距离越短，越不容易跑偏。
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
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
        resignObserver = center.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.persistQueue() }
        }
        backgroundObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.persistQueue() }
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
        clock.set(saved.positionSeconds)
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
            clock.set(0)
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
            clock.freeze()
        } else {
            // 先出声、再落目标位置：在「没开始播」的状态下 seek 最容易被丢掉。
            ensureAudioSessionActive()
            player.play()
            isPlaying = true
            if pendingSeek == nil {
                // 没有待恢复的进度时，以播放器此刻的真实位置为起点。
                clock.set(readPosition())
            }
            // 有待恢复的进度就交给 seek 的回调去写：它写的是真实位置，不是猜的。
            clock.resume()
            applyPendingSeekIfNeeded()
        }
        updateNowPlaying()
        refreshLyricsActivity(force: true)
    }

    func resume() {
        guard player.currentItem != nil else { return }
        ensureAudioSessionActive()
        player.play()
        isPlaying = true
        if pendingSeek == nil { clock.set(readPosition()) }
        clock.resume()
        applyPendingSeekIfNeeded()
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
        clock.set(target)
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
        endLyricsActivity()
        queue = []
        index = -1
        isPlaying = false
        isBuffering = false
        clock.set(0)
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

    /// 当前这首歌实际生效的偏移：调过就用那首歌自己的值，否则用全局值。
    var effectiveLyricOffset: Double {
        LyricOffsetStore.shared.offset(for: current?.id) ?? lyricOffset
    }

    /// 歌词该用的时间轴：外推后的媒体时间 − 输出延迟 − 偏移。
    /// 切行与逐字点亮都用它，两者才不会各偏各的。
    func lyricTime(now: Date = .now) -> Double {
        max(0, clock.live(now: now) - LyricTiming.outputLatency - effectiveLyricOffset)
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
        endLyricsActivity()
        isFavorite = false
        isBuffering = true
        clock.set(0)
        clock.freeze()
        duration = track.durationSeconds ?? 0
        pendingSeek = seekTo
        seekIssuedAt = nil
        seekRetries = 0
        seekInFlight = false
        // 这里不把 clock 写成目标进度：item 还没就绪，seek 可能被丢掉，
        // 那样界面会显示「150 秒」而音频其实从 0 开始，歌词就卡在中间。
        clock.set(0)
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
        clock.set(0)
        clock.freeze()
        seekRetries = 0
        seekIssuedAt = nil
        seekInFlight = false
        // 刚 replaceCurrentItem 时 item 状态是 unknown，此时 seek 会被静默丢弃。
        // 之前正是这样：冷启动恢复进度失败、音频从头播，而歌词已经定位到中间。
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                Task { @MainActor in self?.applyPendingSeekIfNeeded() }
            case .failed:
                Task { @MainActor in self?.pendingSeek = nil }
            default:
                break
            }
        }
        // 兜底：KVO 偶尔会因为 item 已被缓存而错过时机，1.5 秒后再补一次恢复进度。
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.applyPendingSeekIfNeeded()
        }
        if autoplay {
            ensureAudioSessionActive()
            player.play()
            isPlaying = true
            clock.resume()
            // 先出声再落进度：在某些曲目上，只有在播起来之后 seek 才会被真正执行。
            applyPendingSeekIfNeeded()
        } else {
            isPlaying = false
            isBuffering = false
        }
        updateNowPlaying()
        persistQueueSoon()
    }

    /// 把恢复/切歌的目标位置落到已经就绪的 item 上。
    ///
    /// 不能「发起 seek 就算完」：item 刚换、还没真正出声时，AVPlayer 偶尔会把 seek 丢掉，
    /// 回调却照报 finished。那时若把目标清掉、界面又信了它，就成了
    /// 「声音从头开始、进度条停在上一次的位置」——杀后台回来最常见的那一幕。
    /// 所以这里以播放器的真实位置为准，对不上就再试，最多两次。
    private func applyPendingSeekIfNeeded() {
        guard let target = pendingSeek else { return }
        guard target > 0.5 else {
            pendingSeek = nil
            return
        }
        guard let item = player.currentItem, item.status == .readyToPlay else { return }
        guard !seekInFlight else { return }

        seekInFlight = true
        seekIssuedAt = Date()
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                self.seekInFlight = false
                let actual = self.readPosition()
                // 真实位置落在目标 ±1 秒内才算真的落下去。
                if finished, abs(actual - target) <= 1.0 {
                    self.pendingSeek = nil
                    self.clock.set(actual)
                    return
                }
                if self.seekRetries < 2, self.player.currentItem === item {
                    self.seekRetries += 1
                    self.applyPendingSeekIfNeeded()
                    return
                }
                // 实在落不下去就认输：界面跟着音频走，绝不显示一个「不存在」的进度。
                self.pendingSeek = nil
                self.clock.set(actual)
            }
        }
    }

    private func readPosition() -> Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite && seconds >= 0 ? seconds : 0
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
        // 顺手把「是否在走」和校准时刻交给时钟，界面靠它们把 2Hz 补成连续值。
        clock.sync(seconds, running: player.rate > 0)
        // 待恢复的进度迟迟没落下去（音频其实从 0 开始了）：再试一次，还不行就认输，
        // 让进度条跟音频走。没有这一步，seek 被丢掉时进度条会一直停在旧位置，
        // 比从头播更难解释。
        if let target = pendingSeek, player.rate > 0,
           let issued = seekIssuedAt, Date().timeIntervalSince(issued) > 2.5,
           abs(seconds - target) > 3 {
            // 回调迟迟不来也别把后面所有 seek 卡死。
            seekInFlight = false
            if seekRetries < 2 {
                seekRetries += 1
                applyPendingSeekIfNeeded()
            } else {
                pendingSeek = nil
            }
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
        // 换句才真正下发，卡片上的歌词才跟得上唱到哪儿。
        refreshLyricsActivity()
        // 5 秒落一次盘：杀后台时最多丢 5 秒，恢复的进度更贴近真实位置。
        if tickCount % 20 == 0 { persistQueueSoon() }
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

    // MARK: - 锁屏歌词（Live Activity）

    /// 把当前这一句同步到锁屏 / 通知中心的卡片。
    ///
    /// 只在「换句」或「播放状态变了」时才下发：这个回调每 0.25 秒跑一次，
    /// 每次都推一遍既没意义，也会被系统限流、白耗电。
    private func refreshLyricsActivity(force: Bool = false) {
        guard #available(iOS 16.2, *) else { return }
        guard let track = current else { return }
        // 暂停着又没有卡片时不做任何事，别在冷启动恢复时凭空弹一块出来。
        guard isPlaying || lyricsActivity != nil else { return }

        let lines = lyrics.lines
        let index = lines.isEmpty ? -1 : LyricsParser.activeIndex(lines: lines, positionMs: lyricTime() * 1000)
        let currentLine = (index >= 0 && index < lines.count) ? lines[index].text : (lines.first?.text ?? "")
        guard force || index != activityLine || isPlaying != activityPlaying else { return }
        activityLine = index
        activityPlaying = isPlaying

        let next = (index >= 0 && index + 1 < lines.count) ? lines[index + 1].text : nil
        let state = LyricsActivityAttributes.ContentState(
            title: track.title,
            artist: track.artistLine,
            currentLine: currentLine,
            nextLine: (next?.isEmpty == false) ? next : nil,
            isPlaying: isPlaying,
            position: clock.position,
            duration: duration
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity = lyricsActivity {
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        lyricsActivity = try? Activity.request(
            attributes: LyricsActivityAttributes(trackId: track.id),
            content: content,
            pushType: nil
        )
    }

    private func endLyricsActivity() {
        guard #available(iOS 16.2, *) else { return }
        activityLine = -1
        activityPlaying = false
        guard let activity = lyricsActivity else { return }
        lyricsActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
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

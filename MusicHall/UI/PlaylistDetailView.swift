import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist

    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var toast: ToastCenter

    @StateObject private var feed: TrackFeed
    @State private var isPreparing = false

    init(playlist: Playlist) {
        self.playlist = playlist
        _feed = StateObject(wrappedValue: TrackFeed(source: .playlist(id: playlist.id, kind: playlist.kind)))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                header
                if feed.tracks.isEmpty, !feed.isLoading {
                    EmptyHint(
                        title: "这个歌单没有歌曲",
                        detail: "也可能是类型暂不支持（榜单详情尚未接入）。",
                        systemImage: "music.note.list"
                    )
                }
                ForEach(feed.tracks.indices, id: \.self) { index in
                    let track = feed.tracks[index]
                    TrackRow(
                        track: track,
                        isCurrent: player.current?.id == track.id,
                        isPlaying: player.isPlaying
                    ) {
                        player.play(feed.tracks, startIndex: index)
                    }
                    .trackActions(track)
                    .task { await feed.loadMoreIfNeeded(current: track) }
                }
                if feed.isLoading {
                    ProgressView()
                        .tint(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .chromeScrollMargin()
        .background(Theme.bg)
        .navigationTitle(playlist.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await feed.reload() }
        .task {
            feed.onError = { toast.show($0) }
            await feed.reload()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Cover(url: playlist.coverUrl, size: 96, radius: 12, symbol: "music.note.list")
            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(playlist.countLabel ?? playlist.kind.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                if let description = playlist.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    PillButton(
                        title: isPreparing ? "准备中…" : "播放全部",
                        systemImage: "play.fill"
                    ) {
                        playAll()
                    }
                    .disabled(feed.tracks.isEmpty || isPreparing)
                    if feed.isLoading {
                        ProgressView().tint(Theme.muted).scaleEffect(0.7)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }

    private func playAll() {
        Task {
            isPreparing = true
            let tracks = await feed.loadAll()
            isPreparing = false
            guard !tracks.isEmpty else { return }
            player.play(tracks, startIndex: 0)
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var toast: ToastCenter

    @State private var tracks: [Track] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("华为账号播放记录，最多展示最近 200 条")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                    Spacer()
                    PillButton(title: "播放全部", systemImage: "play.fill") {
                        guard !tracks.isEmpty else { return }
                        player.play(tracks, startIndex: 0)
                    }
                    .disabled(tracks.isEmpty)
                }
                .padding(.vertical, 12)

                if tracks.isEmpty, !isLoading {
                    EmptyHint(title: "暂无播放记录", detail: "登录后播放几首就会出现在这里。", systemImage: "clock")
                }

                ForEach(tracks.indices, id: \.self) { index in
                    let track = tracks[index]
                    TrackRow(
                        track: track,
                        isCurrent: player.current?.id == track.id,
                        isPlaying: player.isPlaying
                    ) {
                        player.play(tracks, startIndex: index)
                    }
                    .trackActions(track)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .chromeScrollMargin()
        .background(Theme.bg)
        .navigationTitle("播放历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await refresh() }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard session.isAuthenticated, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            tracks = try await MusicAPI.shared.recent()
        } catch {
            toast.show(error.readableMessage)
        }
    }

    /// 下拉最多等 4 秒；请求本身继续跑，回来仍会写进 tracks。
    private func refresh() async {
        await AwaitCap.run(within: 4) { await load() }
    }
}

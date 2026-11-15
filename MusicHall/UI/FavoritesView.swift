import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var toast: ToastCenter

    @StateObject private var feed = TrackFeed(source: .favorites)
    @State private var isPreparing = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                header
                if feed.tracks.isEmpty, !feed.isLoading {
                    EmptyHint(
                        title: "收藏还是空的",
                        detail: "在官方客户端里收藏几首，这里会自动同步。",
                        systemImage: "heart"
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
                    .trackActions(track, unfavorite: { unfavorite(track) })
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
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await feed.reload() }
        .task {
            feed.onError = { toast.show($0) }
            await feed.reload()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(feed.hasMore ? "已加载 \(feed.tracks.count) 首" : "共 \(feed.tracks.count) 首")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Text(feed.hasMore ? "继续滑动会加载更多" : "已全部加载")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
            PillButton(
                title: isPreparing ? "准备中…" : "播放全部",
                systemImage: "play.fill"
            ) {
                playAll()
            }
            .disabled(feed.tracks.isEmpty || isPreparing)
        }
        .padding(.vertical, 12)
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

    private func unfavorite(_ track: Track) {
        feed.removeLocally(track)
        Task {
            do {
                _ = try await MusicAPI.shared.setFavorite(track.id, favorite: false)
                toast.show("已取消收藏")
            } catch {
                toast.show(error.readableMessage)
                await feed.reload()
            }
        }
    }
}

import Foundation

/// 收藏 / 歌单的共用分页拉取：按真实 contentID 去重，短页即止，失败就停住并保留已加载内容。
@MainActor
final class TrackFeed: ObservableObject {
    enum Source: Equatable {
        case favorites
        case playlist(id: String, kind: PlaylistKind)
    }

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true
    @Published private(set) var loadedTotal: Double?

    var onError: ((String) -> Void)?

    private let source: Source
    private let pageSize: Int
    private var nextStart = 0
    private var seen = Set<String>()

    init(source: Source, pageSize: Int = 50) {
        self.source = source
        self.pageSize = pageSize
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        tracks = []
        seen = []
        nextStart = 0
        hasMore = true
        await appendNextPage()
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        await appendNextPage()
    }

    func loadMoreIfNeeded(current track: Track) async {
        guard tracks.count >= 4,
              let index = tracks.firstIndex(where: { $0.id == track.id }),
              index >= tracks.count - 4
        else { return }
        await loadMore()
    }

    /// 播放全部：先把所有页补齐，再整队播放。
    func loadAll() async -> [Track] {
        while hasMore {
            let before = tracks.count
            await loadMore()
            if tracks.count == before { break }
        }
        return tracks
    }

    func removeLocally(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
    }

    private func appendNextPage() async {
        do {
            let result: (tracks: [Track], hasMore: Bool)
            switch source {
            case .favorites:
                let page = try await MusicAPI.shared.favorites(start: nextStart, limit: pageSize)
                result = (page.tracks, page.hasMore)
            case .playlist(let id, let kind):
                if kind == .collected {
                    let page = try await MusicAPI.shared.publicPlaylist(id: id, start: nextStart, limit: pageSize)
                    result = (page.1, page.2 == pageSize)
                } else {
                    let page = try await MusicAPI.shared.playlistDetail(id: id, start: nextStart, limit: pageSize)
                    result = (page.1, page.2 == pageSize)
                }
            }
            for track in result.tracks where !seen.contains(track.id) {
                seen.insert(track.id)
                tracks.append(track)
            }
            nextStart += pageSize
            hasMore = result.hasMore && !result.tracks.isEmpty
        } catch {
            hasMore = false
            onError?(error.readableMessage)
        }
    }
}

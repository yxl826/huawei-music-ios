import Foundation

struct ArtistRef: Hashable, Codable {
    var id: String?
    var name: String
}

struct AlbumRef: Hashable, Codable {
    var id: String
    var title: String
}

struct Track: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var artists: [ArtistRef]
    var album: AlbumRef?
    var coverUrl: String?
    /// 列表/搜索/歌单接口里随曲目一起下发的歌词地址。播放解析响应里**没有**这个字段，
    /// 所以必须在归一化阶段存下来，否则只能退回逐首搜索。
    var lyricAddress: String?
    var durationSeconds: Double?
    var available: Bool

    init(
        id: String,
        title: String,
        artists: [ArtistRef] = [],
        album: AlbumRef? = nil,
        coverUrl: String? = nil,
        lyricAddress: String? = nil,
        durationSeconds: Double? = nil,
        available: Bool = true
    ) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.coverUrl = coverUrl
        self.lyricAddress = lyricAddress
        self.durationSeconds = durationSeconds
        self.available = available
    }

    var artistLine: String {
        let names = artists.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? "未知歌手" : names.joined(separator: " / ")
    }

    var durationLabel: String {
        guard let durationSeconds, durationSeconds > 0 else { return "--:--" }
        let total = Int(durationSeconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

enum PlaylistKind: String, Codable {
    case owned
    case collected
    case chart
    case unknown

    var label: String {
        switch self {
        case .owned: return "我的歌单"
        case .collected: return "收藏歌单"
        case .chart: return "榜单"
        case .unknown: return "歌单"
        }
    }
}

struct Playlist: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var coverUrl: String?
    var count: Double?
    var kind: PlaylistKind
    var description: String?

    var countLabel: String? {
        guard let count, count > 0 else { return nil }
        return "\(Int(count)) 首"
    }
}

struct LyricsLine: Hashable {
    var timeMs: Double?
    var text: String
    /// 译文：华为歌词里与原文共用时间戳的那一行。
    var translation: String?
    /// 音译：华为把「^」后面的粤语/闽南语罗马音，解析时拆出来的。
    var romanization: String?

    init(timeMs: Double?, text: String, translation: String? = nil, romanization: String? = nil) {
        self.timeMs = timeMs
        self.text = text
        self.translation = translation
        self.romanization = romanization
    }
}

struct LyricsDoc {
    var synced: Bool
    var lines: [LyricsLine]

    static let empty = LyricsDoc(synced: false, lines: [])
}

enum Quality: String, Codable, CaseIterable, Identifiable {
    case standard
    case lossless

    var id: String { rawValue }

    var label: String {
        self == .lossless ? "无损" : "标准"
    }

    var apiValue: String {
        self == .lossless ? "3" : "1"
    }
}

enum PlayMode: String, Codable, CaseIterable, Identifiable {
    case sequential
    case all
    case one
    case shuffle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sequential: return "顺序播放"
        case .all: return "列表循环"
        case .one: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }

    var symbol: String {
        switch self {
        case .sequential: return "arrow.right"
        case .all: return "repeat"
        case .one: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }

    /// 一个按钮四个状态：顺序 → 列表循环 → 单曲循环 → 随机 → 顺序。
    var next: PlayMode {
        switch self {
        case .sequential: return .all
        case .all: return .one
        case .one: return .shuffle
        case .shuffle: return .sequential
        }
    }
}

struct MusicSession: Codable {
    var token: String
    var snsUserID: String?
    var expireTime: String?
    var displayName: String?
}

struct PlaybackInfo {
    var url: URL
    var actualQuality: String
    var contentType: String?
    var durationSeconds: Double?
}

struct SavedQueue: Codable {
    var tracks: [Track]
    var index: Int
    var positionSeconds: Double
}

struct PagedTracks {
    var tracks: [Track]
    var nextStart: Int
    var hasMore: Bool
    var total: Double?
}

struct PagedPlaylists {
    var playlists: [Playlist]
    var truncated: Bool
}

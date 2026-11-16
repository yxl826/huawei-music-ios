import Foundation

struct AppSettings: Codable, Equatable {
    var quality: Quality
    var syncHistory: Bool
    var playMode: PlayMode
    /// 歌词整体延后多少秒（负值提前）。输出延迟因设备/耳机而异，留给用户微调。
    var lyricOffset: Double

    init(quality: Quality, syncHistory: Bool, playMode: PlayMode, lyricOffset: Double = 0) {
        self.quality = quality
        self.syncHistory = syncHistory
        self.playMode = playMode
        self.lyricOffset = lyricOffset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quality = try container.decode(Quality.self, forKey: .quality)
        syncHistory = try container.decode(Bool.self, forKey: .syncHistory)
        playMode = try container.decode(PlayMode.self, forKey: .playMode)
        // 旧版本存下来的数据里没有这一项：给个缺省值，别因为多了一个字段就把设置全丢掉。
        lyricOffset = try container.decodeIfPresent(Double.self, forKey: .lyricOffset) ?? 0
    }

    static let fallback = AppSettings(quality: .standard, syncHistory: true, playMode: .sequential)
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let storageKey = "app-settings-v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = .fallback
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

import Foundation

struct AppSettings: Codable, Equatable {
    var quality: Quality
    var syncHistory: Bool
    var playMode: PlayMode
    /// 歌词整体延后多少秒（负值提前）。输出延迟因设备/耳机而异，留给用户微调。
    var lyricOffset: Double
    /// 原文下面那一行：有音译就显示音译，没有就显示翻译。
    /// 1.6.0 之前这是两个开关，实测一首歌里永远只有其中一个有内容，
    /// 另一个按钮只能是灰的，所以合成一个——和 Apple Music 一样只有一处入口。
    var showLyricSubline: Bool

    init(
        quality: Quality,
        syncHistory: Bool,
        playMode: PlayMode,
        lyricOffset: Double = 0,
        showLyricSubline: Bool = true
    ) {
        self.quality = quality
        self.syncHistory = syncHistory
        self.playMode = playMode
        self.lyricOffset = lyricOffset
        self.showLyricSubline = showLyricSubline
    }

    private enum CodingKeys: String, CodingKey {
        case quality
        case syncHistory
        case playMode
        case lyricOffset
        case showLyricSubline
        /// 1.6.0 及更早的两个旧开关，只读不写，用来把老设置迁过来。
        case legacyShowTranslation = "showTranslation"
        case legacyShowRomanization = "showRomanization"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quality = try container.decode(Quality.self, forKey: .quality)
        syncHistory = try container.decode(Bool.self, forKey: .syncHistory)
        playMode = try container.decode(PlayMode.self, forKey: .playMode)
        // 旧版本存下来的数据里没有这一项：给个缺省值，别因为多了一个字段就把设置全丢掉。
        lyricOffset = try container.decodeIfPresent(Double.self, forKey: .lyricOffset) ?? 0

        if let saved = try container.decodeIfPresent(Bool.self, forKey: .showLyricSubline) {
            showLyricSubline = saved
        } else {
            // 迁移：旧的两个开关只要有一个是开着的，合并后继续显示。
            // 两个键都不在（很老的存档）时按默认打开处理。
            func legacy(_ key: CodingKeys) -> Bool? {
                guard let value = try? container.decodeIfPresent(Bool.self, forKey: key) else { return nil }
                return value
            }
            showLyricSubline = (legacy(.legacyShowTranslation) ?? true) || (legacy(.legacyShowRomanization) ?? false)
        }
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

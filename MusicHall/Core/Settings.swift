import Foundation

struct AppSettings: Codable, Equatable {
    var quality: Quality
    var syncHistory: Bool
    var playMode: PlayMode
    /// 歌词整体延后多少秒（负值提前）。输出延迟因设备/耳机而异，留给用户微调。
    var lyricOffset: Double
    /// 显示中文翻译（网易云的 tlyric）。
    var showTranslation: Bool
    /// 显示音译（粤语/日语的罗马音，网易云的 romalrc）。
    var showRomanization: Bool

    init(
        quality: Quality,
        syncHistory: Bool,
        playMode: PlayMode,
        lyricOffset: Double = 0,
        showTranslation: Bool = true,
        showRomanization: Bool = false
    ) {
        self.quality = quality
        self.syncHistory = syncHistory
        self.playMode = playMode
        self.lyricOffset = lyricOffset
        self.showTranslation = showTranslation
        self.showRomanization = showRomanization
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quality = try container.decode(Quality.self, forKey: .quality)
        syncHistory = try container.decode(Bool.self, forKey: .syncHistory)
        playMode = try container.decode(PlayMode.self, forKey: .playMode)
        // 旧版本存下来的数据里没有这一项：给个缺省值，别因为多了一个字段就把设置全丢掉。
        lyricOffset = try container.decodeIfPresent(Double.self, forKey: .lyricOffset) ?? 0
        showTranslation = try container.decodeIfPresent(Bool.self, forKey: .showTranslation) ?? true
        showRomanization = try container.decodeIfPresent(Bool.self, forKey: .showRomanization) ?? false
    }

    static let fallback = AppSettings(
        quality: .standard,
        syncHistory: true,
        playMode: .sequential,
        showRomanization: true
    )
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let storageKey = "app-settings-v1"
    /// 1.6.0 之前，华为那份歌词把音译缀在原文里，开关管不着，所以看起来「一直有发音」。
    /// 改成上下分行之后发音归开关管，这里替老用户打开一次，免得以为发音丢了。
    private let romanizationMigrationKey = "lyric-romanization-default-v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = .fallback
        }

        if !UserDefaults.standard.bool(forKey: romanizationMigrationKey) {
            settings.showRomanization = true
            UserDefaults.standard.set(true, forKey: romanizationMigrationKey)
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

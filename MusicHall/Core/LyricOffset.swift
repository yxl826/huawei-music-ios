import Foundation

/// 每首歌单独的歌词偏移。
///
/// 全局偏移救不了这件事：不同来源的 LRC 时间轴本身就差半秒到一秒，
/// 遇到前奏不同的版本还能差出好几秒，只能一首一首对。
/// 这里按 trackId 记住用户调过的值，写在本机。
@MainActor
final class LyricOffsetStore {
    static let shared = LyricOffsetStore()

    private let storageKey = "lyric-offsets-v1"
    /// 1.6.2 起第三方歌词会整体对齐到当前音频，时间轴的基准变了：
    /// 之前为「错开的版本」调出来的偏移量继续生效只会越调越错，所以清一次。
    private let realignKey = "lyric-offsets-realigned-v1"
    private var offsets: [String: Double] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: Double].self, from: data) {
            offsets = saved
        }
        if !UserDefaults.standard.bool(forKey: realignKey) {
            offsets.removeAll()
            UserDefaults.standard.set(true, forKey: realignKey)
            persist()
        }
    }

    /// 这首歌调过的偏移；没调过返回 nil，由调用方回落到全局值。
    func offset(for trackId: String?) -> Double? {
        guard let trackId, !trackId.isEmpty else { return nil }
        return offsets[trackId]
    }

    func set(_ value: Double, for trackId: String) {
        guard !trackId.isEmpty else { return }
        let rounded = (value * 100).rounded() / 100
        // 归到 0 就不必留着这条记录，免得越攒越多。
        if abs(rounded) < 0.005 {
            offsets.removeValue(forKey: trackId)
        } else {
            offsets[trackId] = min(15, max(-15, rounded))
        }
        persist()
    }

    func clear(_ trackId: String) {
        offsets.removeValue(forKey: trackId)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(offsets) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

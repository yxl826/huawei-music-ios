import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var session: MusicSession?

    private let account = "music-session"

    var isAuthenticated: Bool { session != nil }

    var accountLabel: String {
        guard let session else { return "未登录" }
        if let name = session.displayName, !name.isEmpty { return name }
        if let sns = session.snsUserID, !sns.isEmpty { return "账号 …\(sns.suffix(4))" }
        return "华为账号"
    }

    var expireLabel: String? {
        guard let expire = session?.expireTime, expire.count >= 8 else { return nil }
        // 已知形态是 14 位 yyyyMMddHHmmss，时区未完全确认，只做粗粒度提示。
        let year = expire.prefix(4)
        let month = expire.dropFirst(4).prefix(2)
        let day = expire.dropFirst(6).prefix(2)
        let hour = expire.dropFirst(8).prefix(2)
        let minute = expire.dropFirst(10).prefix(2)
        if expire.count >= 12 {
            return "会话有效期至 \(year)-\(month)-\(day) \(hour):\(minute)"
        }
        return "会话有效期至 \(year)-\(month)-\(day)"
    }

    init() {
        restore()
    }

    private func restore() {
        guard let data = Keychain.read(account: account),
              let saved = try? JSONDecoder().decode(MusicSession.self, from: data)
        else { return }
        session = saved
        MusicAPI.shared.session = saved
    }

    func adopt(_ newSession: MusicSession) {
        session = newSession
        MusicAPI.shared.session = newSession
        if let data = try? JSONEncoder().encode(newSession) {
            Keychain.save(data, account: account)
        }
    }

    func logout() {
        session = nil
        MusicAPI.shared.session = nil
        Keychain.delete(account: account)
        LyricsService.clearCache()
    }
}

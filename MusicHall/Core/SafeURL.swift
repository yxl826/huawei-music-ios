import Foundation

/// 音频与歌词资源只从华为自有 CDN 取，且必须是 https、不带凭据与端口。
/// 上游桌面版对同一白名单做过实测：kuke 的 HTTP 封面返回 403，同路径 HTTPS 正常。
enum SafeURL {
    private static let allowedSuffixes = [".dbankcdn.cn", ".tingmall.com", ".kuke.com"]

    static func isSafe(_ value: String?) -> Bool {
        guard let value, let components = URLComponents(string: value) else { return false }
        guard components.scheme == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              let host = components.host?.lowercased(),
              !host.isEmpty
        else { return false }
        return allowedSuffixes.contains { host.hasSuffix($0) && host.count > $0.count }
    }

    static func url(_ value: String?) -> URL? {
        guard isSafe(value), let value else { return nil }
        return URL(string: value)
    }
}

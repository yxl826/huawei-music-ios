import CryptoKit
import Foundation

/// 一次登录尝试：PKCE verifier / state 只活这一次，回调消费后作废。
final class LoginAttempt {
    let clientId: String
    let redirectUri: String
    let verifier: String
    let state: String
    let createdAt: Date
    var consumed = false

    init(clientId: String = OAuth.clientId, redirectUri: String = OAuth.redirectUri) {
        self.clientId = clientId
        self.redirectUri = redirectUri
        self.verifier = Random.token(byteCount: 48)
        self.state = Random.token(byteCount: 32)
        self.createdAt = Date()
    }

    var authorizeURL: URL {
        var components = URLComponents(string: OAuth.authorizeEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "scope", value: "openid"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: OAuth.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "countryCode", value: "cn"),
            URLQueryItem(name: "ui_locales", value: "zh-cn")
        ]
        return components.url!
    }
}

enum OAuth {
    static let authorizeEndpoint = "https://oauth-login.platform.hicloud.com/oauth2/v3/authorize"
    static let tokenEndpoint = "https://oauth-login.cloud.huawei.com/oauth2/v3/token"
    /// 公开互操作资料里出现的第三方应用标识，不属于本项目；可能随时失效，仅用于本人账号授权。
    static let clientId = "101444301"
    static let redirectUri = "hms://redirect_uri"
    static let attemptLifetime: TimeInterval = 10 * 60

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString
    }

    static func isCallback(_ url: URL, attempt: LoginAttempt) -> Bool {
        guard let expected = URLComponents(string: attempt.redirectUri),
              let actual = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }
        return actual.scheme?.lowercased() == expected.scheme?.lowercased()
            && actual.host?.lowercased() == expected.host?.lowercased()
            && actual.port == expected.port
            && (actual.path) == (expected.path)
            && actual.user == nil
            && actual.password == nil
            && url.fragment == nil
    }

    /// 只放行华为自有域名的 https 页面，避免登录窗口被带到任意站点。
    static func isAllowedLoginURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "https" || scheme == "http" else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        let roots = ["huawei.com", "hicloud.com", "dbankcloud.cn", "huawei.cn"]
        return roots.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func consumeCallback(_ url: URL, attempt: LoginAttempt) throws -> String {
        guard !attempt.consumed else { throw APIError.invalid("授权回调已使用") }
        let age = Date().timeIntervalSince(attempt.createdAt)
        guard age >= 0, age <= attemptLifetime else { throw APIError.invalid("授权尝试已过期，请重新登录") }
        guard isCallback(url, attempt: attempt) else { throw APIError.invalid("回调地址不匹配") }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        for key in ["state", "code", "error"] where items.filter({ $0.name == key }).count > 1 {
            throw APIError.invalid("回调参数重复")
        }
        let state = items.first { $0.name == "state" }?.value ?? ""
        guard state == attempt.state else { throw APIError.invalid("OAuth state 不匹配") }
        attempt.consumed = true

        if items.contains(where: { $0.name == "error" }) {
            throw APIError.invalid("用户取消授权或授权服务拒绝了请求")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw APIError.invalid("回调缺少授权码")
        }
        return code
    }

    /// 授权码 → 账号访问令牌。这一层不传 client_secret（上游已实测可行），也不代表通用刷新可用。
    static func exchangeCode(_ code: String, attempt: LoginAttempt) async throws -> String {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: attempt.clientId),
            URLQueryItem(name: "redirect_uri", value: attempt.redirectUri),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: attempt.verifier)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Transport.session.data(for: request)
        } catch {
            throw APIError.network("授权码兑换")
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.network("授权码兑换") }
        let json = JSONValue.object(data) ?? [:]
        guard http.statusCode < 400, json["error"] == nil,
              let accessToken = JSONValue.text(json["access_token"])
        else {
            let code = JSONValue.text(json["error"]) ?? "unknown"
            throw APIError.provider(stage: "授权码兑换", status: http.statusCode, code: code)
        }
        return accessToken
    }

    /// 账号令牌 → 音乐会话（loginex）。这一步的 Digest 头不带 token。
    static func exchangeMusicSession(accessToken: String) async throws -> MusicSession {
        let json = try await Transport.post(
            path: "/music-odpapp-service/v5/service/userinfo/loginex",
            body: ["accessToken": accessToken],
            token: nil,
            stage: "音乐会话兑换",
            retry: false
        )
        guard let token = JSONValue.text(json["token"]) else {
            throw APIError.invalid("响应缺少音乐会话令牌")
        }
        let userInfo = JSONValue.dict(json["userInfo"])
        let displayName = JSONValue.text(userInfo["nickName"])
            ?? JSONValue.text(json["nickName"])
            ?? JSONValue.text(json["accountName"])
        return MusicSession(
            token: token,
            snsUserID: JSONValue.text(json["snsUserID"]),
            expireTime: JSONValue.text(json["expireTime"]),
            displayName: displayName
        )
    }
}

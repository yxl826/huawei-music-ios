import Foundation

extension Data {
    /// PKCE verifier / nonce 用的无填充 base64url。
    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum Random {
    static func token(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return Data(bytes).base64URLEncodedString
    }
}

/// 音乐业务请求的唯一出口：Digest 头、25 秒超时、只读请求失败重试一次、写入不重试。
enum Transport {
    static let musicEndpoint = URL(string: "https://api-drcn.music.dbankcloud.cn")!

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Authorization: Digest username=app-music-baseline, nonce=<随机>, created=<UTC ISO8601 无毫秒>[, token=<音乐令牌>]
    static func musicHeaders(token: String?) throws -> [String: String] {
        if let token, token.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n,")) != nil {
            throw APIError.invalid("音乐会话令牌格式无效")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let created = formatter.string(from: Date())
        var authorization = "Digest username=app-music-baseline, nonce=\(Random.token(byteCount: 24)), created=\(created)"
        if let token, !token.isEmpty {
            authorization += ", token=\(token)"
        }
        return ["Content-Type": "application/json", "Authorization": authorization]
    }

    static func post(
        path: String,
        body: JSON,
        token: String?,
        stage: String,
        retry: Bool = true
    ) async throws -> JSON {
        var request = URLRequest(url: musicEndpoint.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        for (key, value) in try musicHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw APIError.invalid("请求参数无法编码")
        }
        return try await execute(request, stage: stage, retry: retry)
    }

    static func get(
        path: String,
        query: [String: String],
        token: String?,
        stage: String
    ) async throws -> JSON {
        var components = URLComponents(
            url: musicEndpoint.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw APIError.invalid("请求地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        for (key, value) in try musicHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await execute(request, stage: stage, retry: true)
    }

    private static func execute(_ request: URLRequest, stage: String, retry: Bool) async throws -> JSON {
        let attempts = retry ? 2 : 1
        var lastError: APIError = .network(stage)
        for attempt in 0..<attempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.network(stage)
                }
                guard let json = JSONValue.object(data) else {
                    throw APIError.provider(stage: stage, status: http.statusCode, code: "unknown", detail: nil)
                }
                let result = JSONValue.dict(json["result"])
                let code = JSONValue.text(result["resultCode"]) ?? "unknown"
                if http.statusCode >= 400 || code != "000000" {
                    throw APIError.provider(stage: stage, status: http.statusCode, code: code,
                                            detail: JSONValue.text(result["resultMsg"]))
                }
                return json
            } catch let error as APIError {
                throw error
            } catch {
                lastError = .network(stage)
                if attempt == attempts - 1 { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw lastError
    }

    /// 有界文本下载（歌词资源），超过 512KB 直接放弃，避免把大文件读进内存。
    static func boundedText(from url: URL, limit: Int = 512 * 1024) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("text/plain,*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw APIError.network("歌词下载")
        }
        guard data.count <= limit else { throw APIError.invalid("歌词资源过大") }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        // 少数歌词资源是 GB18030，给一个明确的兜底编码，不做自动嗅探。
        if let text = String(data: data, encoding: String.Encoding(rawValue: 0x80000632)) {
            return text
        }
        throw APIError.invalid("歌词资源无法解码")
    }
}

import Foundation

/// 网易云歌词：翻译（tlyric）与音译（romalrc）是**独立字段**，
/// 不像华为那样把原文与译文塞在同一行里，所以可以各自开关。
///
/// 用「歌名 + 歌手 + 专辑」搜一次，按标题/歌手/时长打分挑最像的一条；
/// 分数不够就放弃，绝不硬套——宁可回落到华为的歌词，也不要给用户一首错位的词。
enum NeteaseLyrics {
    private static let searchPath = "https://music.163.com/api/search/get/web"
    private static let lyricPath = "https://music.163.com/api/song/lyric"

    private static var headers: [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            "Referer": "https://music.163.com/",
            "Accept": "application/json"
        ]
    }

    static func fetch(track: Track) async throws -> LyricsDoc? {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        // 整个第三方流程给 8 秒预算：拿不到就赶紧回落华为，别让播放页干等。
        let deadline = Date().addingTimeInterval(8)
        let artists = track.artists.map(\.name).filter { !$0.isEmpty }
        let album = track.album?.title

        var candidates: [Candidate] = []
        for query in queries(title: title, artists: artists, album: album) {
            if Date() >= deadline { break }
            candidates.append(contentsOf: await search(query))
            if candidates.count >= 20 { break }
        }
        guard let best = pick(from: candidates, title: title, artists: artists, duration: track.durationSeconds)
        else { return nil }

        return try await lyric(songId: best.id)
    }

    // MARK: - 搜索

    private struct Candidate {
        var id: String
        var name: String
        var artists: [String]
        var duration: Double?   // 秒
        var album: String
    }

    /// 先用「歌名 歌手」，再单独用歌名、歌名 + 专辑兜一遍。
    private static func queries(title: String, artists: [String], album: String?) -> [String] {
        var list: [String] = []
        let main = artists.first ?? ""
        if !main.isEmpty { list.append("\(title) \(main)") }
        list.append(title)
        if let album, !album.isEmpty, !main.isEmpty { list.append("\(title) \(main) \(album)") }
        return list
    }

    private static func search(_ keyword: String) async -> [Candidate] {
        var components = URLComponents(string: searchPath)
        components?.queryItems = [
            URLQueryItem(name: "s", value: keyword),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "20")
        ]
        guard let url = components?.url else { return [] }
        guard let json = await getJSON(url) else { return [] }
        let result = JSONValue.dict(json["result"])
        guard let songs = result["songs"] as? [Any] else { return [] }

        return songs.compactMap { raw -> Candidate? in
            let song = JSONValue.dict(raw)
            guard let id = JSONValue.text(song["id"]), let name = JSONValue.text(song["name"]) else { return nil }
            let artistList = (song["artists"] as? [Any]) ?? []
            let names = artistList.compactMap { JSONValue.text(JSONValue.dict($0)["name"]) }
            let ms = JSONValue.number(song["duration"])
            let albumName = JSONValue.text(JSONValue.dict(song["album"])["name"]) ?? ""
            return Candidate(
                id: id,
                name: name,
                artists: names,
                duration: ms.map { $0 / 1000 },
                album: albumName
            )
        }
    }

    /// 打分挑最近的一条。宁可返回 nil 也不要套错版本。
    private static func pick(
        from candidates: [Candidate],
        title: String,
        artists: [String],
        duration: Double?
    ) -> Candidate? {
        let wantedTitle = normalize(title)
        var best: (candidate: Candidate, score: Double)?

        for candidate in candidates {
            let candidateTitle = normalize(candidate.name)
            var score = 0.0

            if candidateTitle == wantedTitle {
                score += 60
            } else if candidateTitle.hasPrefix(wantedTitle) || candidateTitle.contains(wantedTitle) {
                score += 26
            } else {
                continue
            }

            let matchedArtist = artists.contains { artist in
                let key = normalize(artist)
                guard !key.isEmpty else { return false }
                return candidate.artists.contains { normalize($0).contains(key) || key.contains(normalize($0)) }
            }
            guard matchedArtist else { continue }
            score += 40

            if let duration, let candidateDuration = candidate.duration {
                let diff = abs(candidateDuration - duration)
                if diff <= 3 { score += 20 }
                else if diff <= 8 { score += 12 }
                else if diff <= 20 { score += 4 }
                else if diff > 60 { score -= 15 }
            }

            if let current = best {
                if score > current.score { best = (candidate, score) }
            } else {
                best = (candidate, score)
            }
        }

        guard let best, best.score >= 90 else { return nil }
        return best.candidate
    }

    private static func normalize(_ text: String) -> String {
        // 去掉括号注解、空格与标点，只留文字本身的骨架。
        var cleaned = text
        for pattern in ["\\([^)]*\\)", "（[^）]*）", "\\[[^\\]]*\\]", "【[^】]*】"] {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let dropped = CharacterSet(charactersIn: " \t·・-—_.,，。!！?？'\"“”‘’&")
        var scalars = String.UnicodeScalarView()
        for scalar in cleaned.unicodeScalars
        where !dropped.contains(scalar) && !CharacterSet.punctuationCharacters.contains(scalar) {
            scalars.append(scalar)
        }
        return String(scalars).lowercased()
    }

    // MARK: - 取词

    private static func lyric(songId: String) async throws -> LyricsDoc? {
        var components = URLComponents(string: lyricPath)
        components?.queryItems = [
            URLQueryItem(name: "os", value: "pc"),
            URLQueryItem(name: "id", value: songId),
            URLQueryItem(name: "lv", value: "-1"),
            URLQueryItem(name: "kv", value: "-1"),
            URLQueryItem(name: "tv", value: "-1"),
            URLQueryItem(name: "rv", value: "-1")
        ]
        guard let url = components?.url, let json = await getJSON(url) else { return nil }

        let lrc = JSONValue.text(JSONValue.dict(json["lrc"])["lyric"]) ?? ""
        guard !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let translation = timedLines(JSONValue.text(JSONValue.dict(json["tlyric"])["lyric"]) ?? "")
        let romanization = timedLines(JSONValue.text(JSONValue.dict(json["romalrc"])["lyric"]) ?? "")

        let main = timedLines(lrc)
            .filter { !isCredit($0.value) }
            .sorted { $0.key < $1.key }
        guard !main.isEmpty else { return nil }

        var lines: [LyricsLine] = []
        for (time, text) in main {
            lines.append(
                LyricsLine(
                    timeMs: time,
                    text: text,
                    translation: nearest(time, in: translation),
                    romanization: nearest(time, in: romanization)
                )
            )
        }
        return LyricsDoc(synced: true, lines: lines)
    }

    /// 译文/音译的时间戳未必与原文逐毫秒一致，允许 200ms 内的就近匹配。
    private static func nearest(_ timeMs: Double, in table: [Double: String]) -> String? {
        if let exact = table[timeMs] { return exact }
        var best: (distance: Double, text: String)?
        for (key, text) in table {
            let distance = abs(key - timeMs)
            guard distance <= 200 else { continue }
            if best == nil || distance < best!.distance { best = (distance, text) }
        }
        return best?.text
    }

    private static func timedLines(_ raw: String) -> [Double: String] {
        guard !raw.isEmpty else { return [:] }
        let pattern = try! NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]")
        var result: [Double: String] = [:]

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = pattern.firstMatch(in: line, range: range) else { continue }
            let body = String(line[Range(match.range, in: line)!.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            guard let timeMs = timeMs(from: match, in: line) else { continue }
            // 同一时间戳出现多次时保留第一条，避免覆盖。
            if result[timeMs] == nil { result[timeMs] = body }
        }
        return result
    }

    private static func timeMs(from match: NSTextCheckingResult, in line: String) -> Double? {
        func group(_ index: Int) -> String? {
            guard index < match.numberOfRanges, match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: line)
            else { return nil }
            return String(line[range])
        }
        guard let minutes = group(1), let seconds = group(2) else { return nil }
        var fraction = 0.0
        if let raw = group(3) {
            fraction = (Double(raw) ?? 0) / pow(10, Double(raw.count))
        }
        return (Double(minutes) ?? 0) * 60_000 + (Double(seconds) ?? 0) * 1_000 + fraction * 1_000
    }

    /// 「作词 : 黄家驹」这类制作信息不是歌词，别当歌词行显示。
    private static func isCredit(_ text: String) -> Bool {
        let pattern = "^(作词|作曲|编曲|制作人?|监制|录音|混音|母带|吉他|贝斯|鼓|键盘|和声|出品|发行|原唱|演唱|OP|SP|词|曲)\\s*[:：]"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - 网络

    private static func getJSON(_ url: URL) async -> JSON? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        guard let (data, response) = try? await Transport.session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400
        else { return nil }
        return JSONValue.object(data)
    }
}

import Foundation

/// LRC 解析：支持元信息头、[offset:]、一行多时间戳、双语同时间戳合并。
/// 词级 <mm:ss.xx> 标记只用于剥离，不做卡拉OK高亮。
enum LyricsParser {
    private static let stampPattern = try! NSRegularExpression(
        pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]"
    )
    private static let wordPattern = try! NSRegularExpression(
        pattern: "<(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?>"
    )
    private static let offsetPattern = try! NSRegularExpression(
        pattern: "^\\[offset:\\s*(-?\\d+)\\s*\\]$", options: [.caseInsensitive]
    )
    private static let metadataPattern = try! NSRegularExpression(
        pattern: "^\\[(ti|ar|al|by|re|ve|length)\\s*:.*\\]$", options: [.caseInsensitive]
    )

    static func parse(_ raw: String) -> LyricsDoc {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }

        var offset = 0
        var timed: [(timeMs: Double, text: String)] = []
        var plain: [LyricsLine] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if let captures = firstMatch(offsetPattern, line), captures.count >= 2,
               let rawOffset = captures[1], let value = Double(rawOffset) {
                offset = Int(value)
                continue
            }
            if firstMatch(metadataPattern, line) != nil { continue }

            guard let stamps = allMatches(stampPattern, line), !stamps.isEmpty else {
                plain.append(LyricsLine(timeMs: nil, text: stripWordMarks(line), translation: nil))
                continue
            }

            // 一行多个时间戳时，歌词正文取最后一个时间戳之后的部分。
            let last = stamps[stamps.count - 1]
            let bodyStart = last.range.location + last.range.length
            let body = suffix(line, from: bodyStart).trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyText = stripWordMarks(body)
            // 华为的逐行歌词用「只有时间戳、没有正文」的空行标记上一句结束，
            // 这些行留着会在页面上变成一串空行，直接丢掉。
            if bodyText.isEmpty { continue }

            for stamp in stamps {
                guard stamp.captures.count >= 3,
                      let minutes = stamp.captures[1],
                      let seconds = stamp.captures[2],
                      let timeMs = stampToMs(minutes, seconds, stamp.captures[3], offset: offset)
                else { continue }
                timed.append((timeMs, bodyText))
            }
        }

        if timed.isEmpty {
            return LyricsDoc(synced: false, lines: plain)
        }
        let sorted = timed.sorted { $0.timeMs < $1.timeMs }
        var merged: [LyricsLine] = []
        for entry in sorted {
            if let previous = merged.last,
               previous.timeMs == entry.timeMs,
               previous.translation == nil,
               entry.text != previous.text {
                merged[merged.count - 1].translation = entry.text
                continue
            }
            merged.append(LyricsLine(timeMs: entry.timeMs, text: entry.text, translation: nil))
        }
        return LyricsDoc(synced: true, lines: merged)
    }

    static func activeIndex(_ lines: [LyricsLine], positionMs: Double) -> Int {
        guard !lines.isEmpty, positionMs.isFinite else { return -1 }
        var index = -1
        for (offset, line) in lines.enumerated() {
            guard let time = line.timeMs else { continue }
            if time <= positionMs {
                index = offset
            } else {
                break
            }
        }
        return index
    }

    // MARK: - 正则辅助

    private struct Match {
        var range: NSRange
        var captures: [String?]
    }

    private static func allMatches(_ regex: NSRegularExpression, _ string: String) -> [Match]? {
        let full = NSRange(string.startIndex..<string.endIndex, in: string)
        let results = regex.matches(in: string, options: [], range: full)
        guard !results.isEmpty else { return nil }
        return results.map { match in
            var captures: [String?] = []
            for index in 0..<match.numberOfRanges {
                let range = match.range(at: index)
                if range.location == NSNotFound {
                    captures.append(nil)
                } else {
                    captures.append(Range(range, in: string).map { String(string[$0]) })
                }
            }
            return Match(range: match.range, captures: captures)
        }
    }

    private static func firstMatch(_ regex: NSRegularExpression, _ string: String) -> [String?]? {
        let full = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: full) else { return nil }
        var captures: [String?] = []
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location == NSNotFound {
                captures.append(nil)
            } else {
                captures.append(Range(range, in: string).map { String(string[$0]) })
            }
        }
        return captures
    }

    private static func suffix(_ string: String, from location: Int) -> String {
        guard let index = Range(NSRange(location: location, length: 0), in: string)?.lowerBound else {
            return ""
        }
        return String(string[index...])
    }

    private static func stripWordMarks(_ string: String) -> String {
        let full = NSRange(string.startIndex..<string.endIndex, in: string)
        return wordPattern.stringByReplacingMatches(in: string, options: [], range: full, withTemplate: "")
    }

    private static func stampToMs(_ minutes: String, _ seconds: String, _ fraction: String?, offset: Int) -> Double? {
        guard let m = Double(minutes), let s = Double(seconds), s <= 59 else { return nil }
        var fractionText = fraction ?? ""
        if fractionText.isEmpty { fractionText = "0" }
        if fractionText.count > 3 { fractionText = String(fractionText.prefix(3)) }
        while fractionText.count < 3 { fractionText += "0" }
        let ms = Double(fractionText) ?? 0
        return max(0, m * 60_000 + s * 1_000 + ms + Double(offset))
    }
}

/// 歌词来源按可靠性排序：曲目对象自带地址 → 播放解析响应 → 按歌名搜索精确匹配。
/// 三处都拿不到时返回空文档，并在 `lastDiagnostic` 里写清每一层为什么失败。
enum LyricsService {
    private static var cache: [String: LyricsDoc] = [:]
    private static let cacheLimit = 60
    /// 最近一次没取到歌词的原因，给播放页的空态显示，避免只剩一句「没有歌词」。
    private(set) static var lastDiagnostic: String = ""

    static func cached(_ trackId: String) -> LyricsDoc? {
        cache[trackId]
    }

    static func forget(_ trackId: String) {
        cache.removeValue(forKey: trackId)
        lastDiagnostic = ""
    }

    static func clearCache() {
        cache.removeAll()
        lastDiagnostic = ""
    }

    static func load(track: Track) async -> LyricsDoc {
        if let hit = cache[track.id] { return hit }

        // 0. 第三方（网易云）：按「歌名 + 歌手 + 专辑」搜，命中就优先用。
        //    它的翻译与音译是分开的字段，才能做成开关；华为那份是合在行里的。
        do {
            if let external = try await NeteaseLyrics.fetch(track: track), !external.lines.isEmpty {
                return finish(track.id, external)
            }
        } catch {
            // 第三方失败不是错误，继续走华为。
        }

        var notes: [String] = []

        // 1. 列表/搜索/歌单随曲目下发的地址，命中率最高。
        if let address = track.lyricAddress {
            let (document, note) = await document(from: address)
            if let document { return finish(track.id, document) }
            notes.append("曲目自带地址：\(note)")
        }

        // 2. 播放解析响应：少数曲目只在这里带地址或内嵌歌词。
        let response = try? await MusicAPI.shared.playbackResponse(trackId: track.id, quality: .standard)
        if let response, let address = addressInResponse(response) {
            let (document, note) = await document(from: address)
            if let document { return finish(track.id, document) }
            notes.append("播放响应地址：\(note)")
        } else if let response, let inline = inlineLyrics(response) {
            let document = LyricsParser.parse(inline)
            if !document.lines.isEmpty { return finish(track.id, document) }
            notes.append("播放响应内嵌歌词解析为空")
        } else {
            notes.append("播放响应里没有歌词地址")
        }

        // 3. 兜底：按「歌名 歌手」搜一次，只有 contentID 完全一致才采用，
        //    避免把翻唱或同名 Live 版的歌词套到当前曲目上。
        if let address = await searchedAddress(for: track) {
            let (document, note) = await document(from: address)
            if let document { return finish(track.id, document) }
            notes.append("搜索结果地址：\(note)")
        } else {
            notes.append("按歌名搜索没有匹配到同一首歌")
        }

        lastDiagnostic = notes.joined(separator: "；")
        let empty = LyricsDoc.empty
        store(track.id, empty)
        return empty
    }

    private static func finish(_ trackId: String, _ document: LyricsDoc) -> LyricsDoc {
        store(trackId, document)
        lastDiagnostic = ""
        return document
    }

    private static func store(_ trackId: String, _ document: LyricsDoc) {
        if cache.count >= cacheLimit { cache.removeAll() }
        cache[trackId] = document
    }

    /// 下载并解析一个歌词地址；失败时返回 (nil, 原因)。
    private static func document(from address: String) async -> (LyricsDoc?, String) {
        guard let url = SafeURL.url(address) else {
            let host = URL(string: address)?.host ?? String(address.prefix(40))
            return (nil, "地址不可信（\(host)）")
        }
        do {
            let raw = try await Transport.boundedText(from: url)
            let document = LyricsParser.parse(raw)
            if document.lines.isEmpty {
                return (nil, "文件解析后为空（\(raw.count) 字）")
            }
            return (document, "")
        } catch {
            return (nil, "下载失败：\(error.readableMessage)")
        }
    }

    private static func searchedAddress(for track: Track) async -> String? {
        let query = "\(track.title) \(track.artists.first?.name ?? "")"
            .trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        guard let page = try? await MusicAPI.shared.search(query: query, start: 0, limit: 10) else {
            return nil
        }
        return page.tracks.first { $0.id == track.id && $0.lyricAddress != nil }?.lyricAddress
    }

    private static func extraInfo(_ response: JSON) -> JSON {
        let direct = JSONValue.dict(response["contentExInfo"])
        return direct.isEmpty ? JSONValue.nested(response["contentExInfo"]) : direct
    }

    /// 播放解析响应里若出现歌词地址，按同样的若干拼写找一遍。
    private static func addressInResponse(_ response: JSON) -> String? {
        let extra = extraInfo(response)
        let lyrics = JSONValue.dict(extra["lyrics"])
        let candidates = [
            response["lyricAddress"], response["lyricAddres"],
            extra["lyricAddress"], extra["lyricAddres"],
            lyrics["lyricAddress"], lyrics["lineByLineLyric"],
            JSONValue.dict(response["lyrics"])["lineByLineLyric"]
        ]
        for candidate in candidates where SafeURL.isSafe(JSONValue.text(candidate)) {
            return JSONValue.text(candidate)
        }
        return nil
    }

    private static func inlineLyrics(_ response: JSON) -> String? {
        let extra = extraInfo(response)
        let candidates = [extra["lyrics"], extra["Lyrics"], response["lyrics"], response["Lyrics"]]
        for candidate in candidates {
            if let text = unwrapLyric(candidate, depth: 0) { return text }
        }
        return nil
    }

    private static func unwrapLyric(_ value: Any?, depth: Int) -> String? {
        guard let text = JSONValue.text(value), depth <= 2 else { return nil }
        guard text.count <= 512 * 1024 else { return nil }
        guard text.hasPrefix("{") else { return text }
        guard let data = text.data(using: .utf8), let json = JSONValue.object(data) else { return nil }
        for key in ["lyric", "lyrics", "content", "lrc"] {
            if let nested = unwrapLyric(json[key], depth: depth + 1) { return nested }
        }
        return nil
    }
}

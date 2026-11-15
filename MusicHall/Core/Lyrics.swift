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

/// 歌词来源优先用曲目响应里的地址，其次用内嵌文本；都拿不到就诚实返回空。
enum LyricsService {
    private static var cache: [String: LyricsDoc] = [:]
    private static let cacheLimit = 60

    static func cached(_ trackId: String) -> LyricsDoc? {
        cache[trackId]
    }

    static func clearCache() {
        cache.removeAll()
    }

    static func load(trackId: String) async throws -> LyricsDoc {
        if let hit = cache[trackId] { return hit }
        let response = try await MusicAPI.shared.playbackResponse(trackId: trackId, quality: .standard)

        if let address = lyricAddress(response), let url = SafeURL.url(address) {
            let raw = try? await Transport.boundedText(from: url)
            if let raw {
                let document = LyricsParser.parse(raw)
                if !document.lines.isEmpty {
                    store(trackId, document)
                    return document
                }
            }
        }
        if let inline = inlineLyrics(response) {
            let document = LyricsParser.parse(inline)
            store(trackId, document)
            return document
        }
        let empty = LyricsDoc.empty
        store(trackId, empty)
        return empty
    }

    private static func store(_ trackId: String, _ document: LyricsDoc) {
        if cache.count >= cacheLimit { cache.removeAll() }
        cache[trackId] = document
    }

    private static func extraInfo(_ response: JSON) -> JSON {
        let direct = JSONValue.dict(response["contentExInfo"])
        return direct.isEmpty ? JSONValue.nested(response["contentExInfo"]) : direct
    }

    private static func lyricAddress(_ response: JSON) -> String? {
        let extra = extraInfo(response)
        let lyrics = JSONValue.dict(extra["lyrics"])
        let candidates = [
            response["lyricAddress"], response["lyricAddres"],
            extra["lyricAddress"], extra["lyricAddres"],
            lyrics["lyricAddress"], lyrics["lineByLineLyric"],
            JSONValue.dict(response["lyrics"])["lineByLineLyric"]
        ]
        for candidate in candidates {
            if let text = JSONValue.text(candidate), SafeURL.isSafe(text) { return text }
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

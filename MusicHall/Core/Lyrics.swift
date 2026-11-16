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
        var timed: [(timeMs: Double, text: String, romanization: String?)] = []
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
                let split = splitInlineRomanization(stripWordMarks(line))
                guard !split.text.isEmpty else { continue }
                plain.append(
                    LyricsLine(timeMs: nil, text: split.text, translation: nil, romanization: split.romanization)
                )
                continue
            }

            // 一行多个时间戳时，歌词正文取最后一个时间戳之后的部分。
            let last = stamps[stamps.count - 1]
            let bodyStart = last.range.location + last.range.length
            let body = suffix(line, from: bodyStart).trimmingCharacters(in: .whitespacesAndNewlines)
            // 华为把音译直接缀在原文后面（「人生的风景 ^lin sin ei hon ging」），
            // 这里先拆成原文 + 音译两个字段，渲染层才能像 Apple Music 那样上下两行。
            let split = splitInlineRomanization(stripWordMarks(body))
            // 只有时间戳、没有正文的空行（以及纯音译行）留着会在页面上变成一串空行。
            let bodyText = split.text
            if bodyText.isEmpty {
                // 整行只有音译（「^lin sin ei hon ging」）：挂到上一句上，别丢词。
                if let romanization = split.romanization,
                   !timed.isEmpty, timed[timed.count - 1].romanization == nil {
                    timed[timed.count - 1].romanization = romanization
                }
                continue
            }

            for stamp in stamps {
                guard stamp.captures.count >= 3,
                      let minutes = stamp.captures[1],
                      let seconds = stamp.captures[2],
                      let timeMs = stampToMs(minutes, seconds, stamp.captures[3], offset: offset)
                else { continue }
                timed.append((timeMs, bodyText, split.romanization))
            }
        }

        if timed.isEmpty {
            return LyricsDoc(synced: false, lines: plain)
        }
        let sorted = timed.sorted { $0.timeMs < $1.timeMs }
        var merged: [LyricsLine] = []
        for entry in sorted where !isCredit(entry.text) {
            if let previous = merged.last {
                // 同一时间戳、同一句＝重复行，丢掉。
                if previous.timeMs == entry.timeMs, previous.text == entry.text { continue }
                // 同一时间戳的第二行**未必**是译文：华为的国语歌词里常见两句共用一个时间戳，
                // 之前一律当成译文，于是正文被塞进 translation 变成了小字。
                // 只有「两行文字体系不同」（外语原文 + 中文译文）才合并。
                if previous.timeMs == entry.timeMs,
                   previous.translation == nil,
                   entry.romanization == nil,
                   isTranslation(entry.text, of: previous.text) {
                    merged[merged.count - 1].translation = entry.text
                    continue
                }
            }
            merged.append(
                LyricsLine(
                    timeMs: entry.timeMs,
                    text: entry.text,
                    translation: nil,
                    romanization: entry.romanization
                )
            )
        }
        return LyricsDoc(synced: true, lines: merged)
    }

    /// 文字的「体系」：判断第二行到底是译文还是另一句歌词。
    private enum Script {
        case cjk      // 汉字
        case kana     // 日文假名
        case hangul   // 谚文
        case latin    // 拉丁字母
        case other
    }

    private static func script(of text: String) -> Script {
        var han = 0, kana = 0, hangul = 0, latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF: kana += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF: hangul += 1
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: han += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        if kana > 0 { return .kana }
        if hangul > 0 { return .hangul }
        if han > 0 { return .cjk }
        if latin > 0 { return .latin }
        return .other
    }

    /// 只有文字体系不同才当译文：双语歌词的译文几乎总是另一种文字。
    /// 两行都是汉字（国语歌词换了行/换了口气）就不合并，各自成行。
    private static func isTranslation(_ candidate: String, of original: String) -> Bool {
        let a = script(of: original)
        let b = script(of: candidate)
        guard a != b else { return false }
        if b == .cjk { return true }          // 外语原词 + 中文译文（最常见）
        if a == .cjk { return true }          // 中文原词 + 英/日译文
        return false
    }

    /// 华为的歌词把音译缀在原文后面，用「^」分隔（如「人生的风景 ^lin sin ei hon ging」）。
    /// Apple Music 是「原文一行、音译一行」的上下结构，所以入库前先拆成两个字段。
    static func splitInlineRomanization(_ body: String) -> (text: String, romanization: String?) {
        guard let caret = body.firstIndex(where: { $0 == "^" || $0 == "＾" }) else {
            return (body, nil)
        }
        let head = String(body[body.startIndex..<caret]).trimmingCharacters(in: .whitespaces)
        let tail = String(body[body.index(after: caret)...]).trimmingCharacters(in: .whitespaces)
        guard !tail.isEmpty else { return (head, nil) }
        return (head, tail)
    }

    /// 「作词 : 某某」「曲：伍佰」这类制作信息不是歌词，播放页里不该滚过去。
    private static func isCredit(_ text: String) -> Bool {
        let pattern = "^(作词|作曲|编曲|制作人?|监制|录音|混音|母带|吉他|贝斯|鼓|键盘|和声|出品|发行|原唱|演唱|OP|SP|词|曲)\\s*[:：]"
        return text.range(of: pattern, options: .regularExpression) != nil
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

        // 先把华为那份拿到手：它是对着这份音频做的，既当兜底，也给第三方的时间轴当尺子。
        let (local, notes) = await localDocument(track: track)

        // 第三方（网易云）：按「歌名 + 歌手 + 专辑」搜索，命中就优先用。
        // 它的翻译与音译是分开的字段，才能做成开关。但它的时间轴是按**它自家那份音频**
        // 标的，遇到前奏长度不同的版本就会整首错开，所以要么对齐、要么放弃。
        var external: LyricsDoc?
        do {
            external = try await NeteaseLyrics.fetch(track: track)
        } catch {
            external = nil
        }
        if let external, !external.lines.isEmpty, timelinePlausible(external, track: track) {
            return finish(track.id, alignedToLocal(external, local: local))
        }

        if let local { return finish(track.id, local) }

        lastDiagnostic = notes.joined(separator: "；")
        let empty = LyricsDoc.empty
        store(track.id, empty)
        return empty
    }

    /// 华为那份的三级来源：曲目自带地址 → 播放解析响应 → 按歌名搜索（contentID 必须一致）。
    /// 同时带回落空的原因，给播放页的空态显示。
    private static func localDocument(track: Track) async -> (LyricsDoc?, [String]) {
        var notes: [String] = []

        if let address = track.lyricAddress {
            let (document, note) = await document(from: address)
            if let document { return (document, notes) }
            notes.append("曲目自带地址：\(note)")
        }

        let response = try? await MusicAPI.shared.playbackResponse(trackId: track.id, quality: .standard)
        if let response, let address = addressInResponse(response) {
            let (document, note) = await document(from: address)
            if let document { return (document, notes) }
            notes.append("播放响应地址：\(note)")
        } else if let response, let inline = inlineLyrics(response) {
            let document = LyricsParser.parse(inline)
            if !document.lines.isEmpty { return (document, notes) }
            notes.append("播放响应内嵌歌词解析为空")
        } else {
            notes.append("播放响应里没有歌词地址")
        }

        if let address = await searchedAddress(for: track) {
            let (document, note) = await document(from: address)
            if let document { return (document, notes) }
            notes.append("搜索结果地址：\(note)")
        } else {
            notes.append("按歌名搜索没有匹配到同一首歌")
        }
        return (nil, notes)
    }

    /// 时间轴是否对得上这份音频：最后一句不该落在整首歌结束之后。
    /// 常见错法是匹配到了 Live / 加长版，歌词整整多出一分钟。
    private static func timelinePlausible(_ document: LyricsDoc, track: Track) -> Bool {
        guard let duration = track.durationSeconds, duration > 30,
              let last = document.lines.compactMap(\.timeMs).max()
        else { return true }
        let lastSeconds = last / 1000
        guard lastSeconds <= duration + 8 else { return false }
        guard lastSeconds >= duration * 0.35 else { return false }
        return true
    }

    /// 用华为那份的时间轴当尺子，把第三方那份整体挪过去。
    ///
    /// 两边按歌词文本配对（去掉空格标点），取时间差的中位数：
    /// 同一首歌的两个版本若前奏差了 5 秒，中位数就是 5，整份挪完就对齐了。
    /// 配对太少说明不是同一首歌的同一套词，宁可不动。
    private static func alignedToLocal(_ external: LyricsDoc, local: LyricsDoc?) -> LyricsDoc {
        guard let local, local.lines.count >= 6 else { return external }

        var reference: [String: Double] = [:]
        for line in local.lines {
            guard let time = line.timeMs else { continue }
            let key = alignKey(line.text)
            guard !key.isEmpty, reference[key] == nil else { continue }
            reference[key] = time
        }
        guard reference.count >= 4 else { return external }

        var deltas: [Double] = []
        for line in external.lines {
            guard let time = line.timeMs, let base = reference[alignKey(line.text)] else { continue }
            deltas.append(time - base)
        }
        // 至少要配上三分之一，否则可能压根不是同一首歌。
        guard deltas.count >= max(4, external.lines.count / 3) else { return external }

        let sorted = deltas.sorted()
        let median = sorted[sorted.count / 2]
        // 半秒以内属于两份 LRC 的正常误差，不动；差到几十秒说明配错了，也不动。
        guard abs(median) >= 0.25, abs(median) <= 30 else { return external }

        var shifted = external
        shifted.lines = external.lines.map { line in
            var copy = line
            if let time = line.timeMs { copy.timeMs = max(0, time - median) }
            return copy
        }
        return shifted
    }

    /// 配对用的键：去掉空格与标点，只留文字本身。
    private static func alignKey(_ text: String) -> String {
        let dropped = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !dropped.contains(scalar) {
            scalars.append(scalar)
        }
        return String(scalars).lowercased()
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

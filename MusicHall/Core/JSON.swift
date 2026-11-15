import Foundation

/// 华为音乐接口返回的是结构松散的 JSON（同一字段在不同接口里有多种拼写），
/// 这里统一用 [String: Any] + 归一化函数解析，不做 Codable 硬解，避免字段漂移直接抛错。
typealias JSON = [String: Any]

enum JSONValue {
    static func object(_ data: Data) -> JSON? {
        guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return value as? JSON
    }

    /// 去掉首尾空白的非空字符串。
    static func text(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 原样字符串（歌词等需要保留换行/空白的场合）。
    static func raw(_ value: Any?) -> String? {
        value as? String
    }

    /// 错误码可能是数字（华为 OAuth 返回 `"error": 1103`）也可能是字符串，统一成文本。
    static func code(_ value: Any?) -> String? {
        if let string = text(value) { return string }
        if let number = number(value), number < 10_000_000 { return String(Int(number)) }
        return nil
    }

    static func number(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String {
            guard let parsed = Double(string), parsed.isFinite, parsed >= 0 else { return nil }
            return parsed
        }
        if let number = value as? NSNumber {
            if String(cString: number.objCType) == "c" { return nil }
            let parsed = number.doubleValue
            guard parsed.isFinite, parsed >= 0 else { return nil }
            return parsed
        }
        return nil
    }

    static func list(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    static func objects(_ value: Any?) -> [JSON] {
        list(value).compactMap { $0 as? JSON }
    }

    static func dict(_ value: Any?) -> JSON {
        value as? JSON ?? [:]
    }

    /// contentExInfo 常常是「JSON 字符串」，必须二次解析；解析失败就当没有。
    static func nested(_ value: Any?) -> JSON {
        guard let raw = value as? String, let data = raw.data(using: .utf8) else { return [:] }
        return object(data) ?? [:]
    }

    static func contentType(_ value: Any?) -> String? {
        guard let raw = value else { return nil }
        if raw is NSNull { return nil }
        if let string = raw as? String { return string.isEmpty ? nil : string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }

    /// 14 位 UTC 时间戳，写接口（歌单创建、历史上报）要求的形式。
    static func timestamp14(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date)
    }
}

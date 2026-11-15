import Foundation

/// 不把供应商返回的错误原文整段塞进界面：对方可能在响应里回显凭据。
/// `detail` 只放短的结构化说明（如 "invalid code"），用于排查，长度受限且去掉换行。
enum APIError: LocalizedError {
    case network(String)
    case provider(stage: String, status: Int, code: String, detail: String?)
    case invalid(String)
    case needsLogin

    var errorDescription: String? {
        switch self {
        case .network(let stage):
            return "\(stage)失败，请检查网络后重试。"
        case .provider(let stage, let status, let code, let detail):
            var text = "\(stage)失败（HTTP \(status)"
            if code != "unknown" { text += " · \(code)" }
            if let detail, !detail.isEmpty { text += "：\(detail)" }
            return text + "）"
        case .invalid(let message):
            return message
        case .needsLogin:
            return "登录状态已失效，请重新登录。"
        }
    }

    var isAuthFailure: Bool {
        switch self {
        case .needsLogin:
            return true
        case .provider(_, let status, let code, _):
            return status == 401 || status == 403 || code == "401" || code == "403"
        default:
            return false
        }
    }

    /// 授权码已用过或已过期（华为返回 1103 invalid code）。这种情况下重试同一段 code 没有意义。
    var isInvalidGrant: Bool {
        if case .provider(_, _, let code, let detail) = self {
            return code == "1103" || (detail?.lowercased().contains("invalid code") ?? false)
        }
        return false
    }
}

extension Error {
    var readableMessage: String {
        if let apiError = self as? APIError, let description = apiError.errorDescription {
            return description
        }
        if let localized = self as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return (self as NSError).localizedDescription
    }
}

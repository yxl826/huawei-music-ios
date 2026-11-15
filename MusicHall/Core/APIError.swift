import Foundation

/// 不把供应商返回的错误原文塞进界面：对方可能在响应里回显凭据。
enum APIError: LocalizedError {
    case network(String)
    case provider(stage: String, status: Int, code: String)
    case invalid(String)
    case needsLogin

    var errorDescription: String? {
        switch self {
        case .network(let stage):
            return "\(stage)失败，请检查网络后重试。"
        case .provider(let stage, let status, let code):
            return code == "unknown"
                ? "\(stage)失败（HTTP \(status)）"
                : "\(stage)失败（HTTP \(status) · \(code)）"
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
        case .provider(_, let status, let code):
            return status == 401 || status == 403 || code == "401" || code == "403"
        default:
            return false
        }
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

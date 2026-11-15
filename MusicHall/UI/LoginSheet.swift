import AuthenticationServices
import SwiftUI
import UIKit
import WebKit

@MainActor
final class LoginModel: ObservableObject {
    @Published var statusText = "正在打开华为官方登录页…"
    @Published var errorMessage: String?
    @Published var isExchanging = false
    @Published var attemptID = UUID()

    private(set) var attempt = LoginAttempt()
    private var handled = false
    var onSuccess: ((MusicSession) -> Void)?

    var authorizeURL: URL { attempt.authorizeURL }

    func restart() {
        attempt = LoginAttempt()
        attemptID = UUID()
        handled = false
        errorMessage = nil
        isExchanging = false
        statusText = "请重新在官方页面完成授权。"
    }

    /// 返回 true 表示这次导航已被本层处理（回调或需要拦截）。
    func handle(_ url: URL) -> Bool {
        if handled { return true }
        guard OAuth.isCallback(url, attempt: attempt) else { return false }
        handled = true
        do {
            let code = try OAuth.consumeCallback(url, attempt: attempt)
            statusText = "授权成功，正在换取音乐会话…"
            isExchanging = true
            Task { await exchange(code: code) }
        } catch {
            errorMessage = error.readableMessage
        }
        return true
    }

    func exchange(code: String) async {
        do {
            let accessToken = try await OAuth.exchangeCode(code, attempt: attempt)
            let session = try await OAuth.exchangeMusicSession(accessToken: accessToken)
            isExchanging = false
            onSuccess?(session)
        } catch {
            isExchanging = false
            if let apiError = error as? APIError, apiError.isInvalidGrant {
                // 授权码只能用一次、几分钟就过期：卡在这里重试同一段 code 永远失败，
                // 直接把登录页换成新的一次尝试，让用户再登录一遍。
                let detail = apiError.errorDescription ?? "授权码已失效"
                restart()
                errorMessage = "\(detail)。登录页已刷新，请重新授权。"
                return
            }
            errorMessage = error.readableMessage
        }
    }

    func startSystemBrowser(anchor: ASPresentationAnchor?) {
        guard let anchor, !isExchanging else { return }
        let session = ASWebAuthenticationSession(
            url: authorizeURL,
            callbackURLScheme: "hms"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                if let callbackURL {
                    _ = self.handle(callbackURL)
                    return
                }
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    self.errorMessage = "已取消系统浏览器登录。"
                } else if let error {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        // 两个对象都必须被持有，否则系统浏览器弹不出来。
        let provider = AnchorProvider(anchor: anchor)
        anchorProvider = provider
        session.presentationContextProvider = provider
        session.prefersEphemeralWebBrowserSession = true
        _ = session.start()
        systemSession = session
    }

    private var systemSession: ASWebAuthenticationSession?
    private var anchorProvider: AnchorProvider?
}

final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

/// 官方登录页装在这个独立 WebView 里：无持久 Cookie、无 JS 注入、只放行华为域名。
struct LoginWebView: UIViewRepresentable {
    let url: URL
    let onNavigation: (URL) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: LoginWebView

        init(parent: LoginWebView) {
            self.parent = parent
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if parent.onNavigation(url) {
                decisionHandler(.cancel)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme != "https" && scheme != "http" {
                // 自定义 scheme 一律拦掉：只有 hms:// 回调有意义，已经在上一步处理。
                decisionHandler(.cancel)
                return
            }
            decisionHandler(OAuth.isAllowedLoginURL(url) ? .allow : .cancel)
        }
    }
}

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = LoginModel()

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Rectangle().fill(Theme.line).frame(height: 1)

                if let error = model.errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.like)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Button("重试") { model.restart() }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
                }

                LoginWebView(url: model.authorizeURL) { url in
                    model.handle(url)
                }
                .id(model.attemptID)
                .background(Theme.bg)

                bottomBar
            }

            if model.isExchanging {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().tint(Theme.text)
                    Text(model.statusText)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                }
                .padding(24)
                .panel()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.onSuccess = { newSession in
                session.adopt(newSession)
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("登录华为账号")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("在官方页面上完成扫码或短信登录，密码不经过本应用")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 4)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30, height: 30)
                    .background(Theme.surface2, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var bottomBar: some View {
        HStack {
            Text(model.statusText)
                .font(.system(size: 10))
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                model.startSystemBrowser(anchor: keyWindow)
            } label: {
                Text("改用系统浏览器")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.bg)
    }

    private var keyWindow: ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

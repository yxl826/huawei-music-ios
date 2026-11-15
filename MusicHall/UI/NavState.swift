import SwiftUI

@MainActor
final class NavState: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var showSearch = false
    @Published var showLogin = false
    @Published var showPlayer = false
    @Published var showQueue = false
    @Published var showSettings = false

    func requireLogin() -> Bool {
        if SessionBridge.isAuthenticated {
            return false
        }
        showLogin = true
        return true
    }
}

/// 让非 SwiftUI 层（视图里的闭包）能读到登录态，避免到处传 EnvironmentObject。
@MainActor
enum SessionBridge {
    static weak var store: SessionStore?

    static var isAuthenticated: Bool { store?.isAuthenticated ?? false }

    static func bind(_ store: SessionStore) {
        self.store = store
    }
}

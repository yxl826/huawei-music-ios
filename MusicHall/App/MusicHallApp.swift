import SwiftUI
import UIKit

@main
struct MusicHallApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var player = PlayerEngine()
    @StateObject private var nav = NavState()
    @StateObject private var toast = ToastCenter()

    init() {
        Self.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(settings)
                .environmentObject(player)
                .environmentObject(player.clock)
                .environmentObject(nav)
                .environmentObject(toast)
                .preferredColorScheme(.dark)
        }
    }

    /// 导航栏统一压成近黑。TabBar 只在 iOS 26 以下才自定义——
    /// iOS 26 的系统 TabBar 自带 Liquid Glass 和选中态滑动，覆盖外观等于把它关掉。
    private static func configureAppearance() {
        if #unavailable(iOS 26.0) {
            let tabAppearance = UITabBarAppearance()
            tabAppearance.configureWithOpaqueBackground()
            tabAppearance.backgroundColor = UIColor(Theme.bg)
            tabAppearance.shadowColor = UIColor.white.withAlphaComponent(0.07)

            let itemAppearance = tabAppearance.stackedLayoutAppearance
            itemAppearance.normal.iconColor = UIColor(Theme.faint)
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.faint)]
            itemAppearance.selected.iconColor = UIColor(Theme.text)
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]

            UITabBar.appearance().standardAppearance = tabAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        }

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = UIColor(Theme.bg)
        navigationAppearance.shadowColor = UIColor.white.withAlphaComponent(0.07)
        navigationAppearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        navigationAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = UIColor(Theme.text)
    }
}

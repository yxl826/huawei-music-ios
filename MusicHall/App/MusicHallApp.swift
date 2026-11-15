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
                .environmentObject(nav)
                .environmentObject(toast)
                .preferredColorScheme(.dark)
        }
    }

    /// 系统 TabBar / 导航栏统一压成近黑，去掉半透明毛玻璃的白边。
    private static func configureAppearance() {
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

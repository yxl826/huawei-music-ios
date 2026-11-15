import SwiftUI

struct RootView: View {
    @EnvironmentObject private var nav: NavState
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var toast: ToastCenter

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $nav.tab) {
                NavigationStack {
                    HomeView()
                }
                .miniPlayerOverlayIfNeeded()
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.activeSymbol)
                }
                .tag(AppTab.home)

                NavigationStack {
                    HallView()
                }
                .miniPlayerOverlayIfNeeded()
                .tabItem {
                    Label(AppTab.hall.title, systemImage: AppTab.hall.activeSymbol)
                }
                .tag(AppTab.hall)

                NavigationStack {
                    LibraryView()
                }
                .miniPlayerOverlayIfNeeded()
                .tabItem {
                    Label(AppTab.library.title, systemImage: AppTab.library.activeSymbol)
                }
                .tag(AppTab.library)
            }
            .tint(Theme.like)
            // iOS 26 起交给系统：底部附属视图会贴着 dock 绘制，宽度、圆角、玻璃都和 dock 一致。
            .miniPlayerAccessory()

            toastOverlay
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $nav.showLogin) {
            LoginSheet()
        }
        .sheet(isPresented: $nav.showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { nav.showSettings = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $nav.showPlayer) {
            PlayerView()
        }
        .fullScreenCover(isPresented: $nav.showSearch) {
            NavigationStack {
                SearchView()
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: player.errorMessage) { message in
            guard let message, !message.isEmpty else { return }
            toast.show(message)
            player.errorMessage = nil
        }
        .onChange(of: settings.settings.quality) { value in
            player.quality = value
        }
        .onChange(of: settings.settings.syncHistory) { value in
            player.syncHistory = value
        }
        .onChange(of: session.isAuthenticated) { authenticated in
            if authenticated {
                player.restoreQueue()
            }
        }
        .onAppear(perform: wire)
    }

    /// 把设置与播放内核接起来：只在 onAppear 里拿真实对象，闭包里不碰 StateObject。
    private func wire() {
        SessionBridge.bind(session)
        let engine = player
        let settingsStore = settings
        let sessionStore = session
        engine.persistMode = {
            settingsStore.settings.playMode = engine.mode
        }
        engine.mode = settingsStore.settings.playMode
        engine.quality = settingsStore.settings.quality
        engine.syncHistory = settingsStore.settings.syncHistory
        if sessionStore.isAuthenticated {
            engine.restoreQueue()
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toast.message {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface3, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                .padding(.horizontal, 40)
                .padding(.bottom, player.current == nil ? 78 : MiniPlayerCard.height + 34)
                .transition(.opacity)
        }
    }
}

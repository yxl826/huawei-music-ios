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
                .bottomChromeInset()
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.activeSymbol)
                }
                .tag(AppTab.home)

                NavigationStack {
                    HallView()
                }
                .bottomChromeInset()
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(AppTab.hall.title, systemImage: AppTab.hall.activeSymbol)
                }
                .tag(AppTab.hall)

                NavigationStack {
                    SearchView()
                }
                .bottomChromeInset()
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(AppTab.search.title, systemImage: AppTab.search.symbol)
                }
                .tag(AppTab.search)

                NavigationStack {
                    LibraryView()
                }
                .bottomChromeInset()
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(AppTab.library.title, systemImage: AppTab.library.activeSymbol)
                }
                .tag(AppTab.library)
            }
            .tint(Theme.text)

            BottomChrome(tab: $nav.tab)

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
                .padding(.bottom, player.current == nil ? 86 : BottomChrome.insetHeight(hasTrack: true) + 8)
                .transition(.opacity)
        }
    }
}

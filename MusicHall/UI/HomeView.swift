import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState
    @EnvironmentObject private var toast: ToastCenter

    @State private var history: [Track] = []
    @State private var favorites: [Track] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var retriedAfterColdStart = false
    @State private var showedLoadError = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header

                if !session.isAuthenticated {
                    LoginPrompt(
                        title: "还没登录",
                        detail: "登录你自己的华为账号后，这里会显示最近播放和收藏。能听什么完全取决于账号已有的权益。"
                    ) {
                        nav.showLogin = true
                    }
                }

                continueListening
                recentSection
                favoritesSection
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 26)
        }
        .chromeScrollMargin()
        .background(Theme.bg)
        .scrollIndicators(.hidden)
        .refreshable { await load(timeout: 4) }
        .overlay(alignment: .topTrailing) {
            TopActionBar()
                .padding(.trailing, Theme.pagePadding)
                .padding(.top, 2)
        }
        .task { await load() }
        .onChange(of: session.isAuthenticated) { _ in
            Task { await load() }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(session.isAuthenticated ? "从你自己的音乐库里接着听" : "非官方客户端 · 需要你自己的华为账号")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    // MARK: - 继续听

    @ViewBuilder
    private var continueListening: some View {
        if let track = player.current {
            HStack(spacing: 13) {
                Cover(url: track.coverUrl, size: 66, radius: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("继续听")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(track.artistLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(width: 40, height: 40)
                        .background(Theme.primary, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .panel(radius: Theme.radiusXL)
            .onTapGesture { nav.showPlayer = true }
        }
    }

    // MARK: - 最近播放

    @ViewBuilder
    private var recentSection: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "最近播放", subtitle: "来自账号的播放记录")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(history.indices, id: \.self) { index in
                            let track = history[index]
                            CoverCard(
                                title: track.title,
                                subtitle: track.artistLine,
                                coverUrl: track.coverUrl
                            ) {
                                player.play(history, startIndex: index)
                            }
                            .trackActions(track)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    // MARK: - 收藏速览

    @ViewBuilder
    private var favoritesSection: some View {
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "我的收藏", subtitle: "点封面直接开播")
                    NavigationLink {
                        FavoritesView()
                    } label: {
                        Text("全部")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(0..<min(20, favorites.count), id: \.self) { index in
                            let track = favorites[index]
                            CoverCard(
                                title: track.title,
                                subtitle: track.artistLine,
                                coverUrl: track.coverUrl
                            ) {
                                player.play(Array(favorites.prefix(20)), startIndex: index)
                            }
                            .trackActions(track)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    // MARK: - 数据

    /// 包一层拿到可选值：两个请求各失败各的，不互相牵连。
    private func fetchRecent() async -> [Track]? {
        try? await MusicAPI.shared.recent()
    }

    private func fetchFavorites() async -> (entries: [JSON], tracks: [Track], hasMore: Bool)? {
        try? await MusicAPI.shared.favorites(start: 0, limit: 20)
    }

    @MainActor
    private func load(timeout: Double = 10) async {
        guard session.isAuthenticated else {
            history = []
            favorites = []
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            loadedOnce = true
        }

        // 两个请求分别看待成败：播放历史挂了不该把收藏一起清空，
        // 否则冷启动时一个抖动就让整页变空。各自把结果写进状态，
        // 超时先返回时数据回来也能自动补上。
        let recentTask = Task { @MainActor in
            guard let recent = await fetchRecent() else { return false }
            history = Array(recent.prefix(20))
            return true
        }
        let favoritesTask = Task { @MainActor in
            guard let page = await fetchFavorites() else { return false }
            favorites = page.tracks
            return true
        }

        let recentOK = await AwaitCap.value(of: recentTask, within: timeout) ?? false
        let favoritesOK = await AwaitCap.value(of: favoritesTask, within: timeout) ?? false

        guard !recentOK || !favoritesOK else { return }
        // 冷启动最常见的情况是网络还没就绪，重试一次通常就好，
        // 所以先静默重来，不在界面上弹错误。
        if !retriedAfterColdStart {
            retriedAfterColdStart = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await load()
            }
            return
        }
        if history.isEmpty, favorites.isEmpty, !showedLoadError {
            showedLoadError = true
            toast.show("内容没加载出来，下拉可以再试一次。")
        }
    }
}

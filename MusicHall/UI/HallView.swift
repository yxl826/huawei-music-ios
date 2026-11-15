import SwiftUI
import UIKit

struct HallView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState
    @EnvironmentObject private var toast: ToastCenter

    @State private var playlists: [Playlist] = []
    @State private var favorites: [Track] = []
    @State private var picks: [Track] = []
    @State private var isLoading = false
    @State private var loadedOnce = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                PageTitle(title: "音乐厅", subtitle: "你的歌单与收藏精选")

                if !session.isAuthenticated {
                    LoginPrompt(
                        title: "登录后才有内容",
                        detail: "音乐厅里的歌单和收藏都来自你自己的账号，客户端不提供任何音源。"
                    ) {
                        nav.showLogin = true
                    }
                }

                if !playlists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "我的歌单",
                            subtitle: "自建与收藏的歌单"
                        )
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(playlists.prefix(6)) { playlist in
                                playlistCell(playlist)
                            }
                        }
                    }
                }

                if !picks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "收藏精选",
                            subtitle: "从你的收藏里随手挑几首",
                            actionTitle: "换一批",
                            action: { shufflePicks() }
                        )
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Array(picks.enumerated()), id: \.offset) { offset, track in
                                CoverCard(
                                    title: track.title,
                                    subtitle: track.artistLine,
                                    coverUrl: track.coverUrl,
                                    width: gridCoverWidth
                                ) {
                                    player.play(picks, startIndex: offset)
                                }
                                .trackActions(track)
                            }
                        }
                    }
                }

                if session.isAuthenticated, !isLoading, playlists.isEmpty, picks.isEmpty {
                    EmptyHint(
                        title: "还没有歌单或收藏",
                        detail: "在官方客户端里建一个歌单，这里就会出现。",
                        systemImage: "rectangle.stack"
                    )
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 26)
        }
        .background(Theme.bg)
        .scrollIndicators(.hidden)
        .overlay(alignment: .topTrailing) {
            TopActionBar()
                .padding(.trailing, Theme.pagePadding)
                .padding(.top, 2)
        }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: session.isAuthenticated) { _ in
            Task { await load() }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var gridCoverWidth: CGFloat {
        let width = UIScreen.main.bounds.width - Theme.pagePadding * 2
        return max(120, (width - 12) / 2)
    }

    @ViewBuilder
    private func playlistCell(_ playlist: Playlist) -> some View {
        if playlist.kind == .owned || playlist.kind == .collected {
            NavigationLink {
                PlaylistDetailView(playlist: playlist)
            } label: {
                CoverTile(
                    title: playlist.title,
                    subtitle: playlist.countLabel ?? playlist.kind.label,
                    coverUrl: playlist.coverUrl,
                    width: gridCoverWidth,
                    symbol: "music.note.list"
                )
            }
            .buttonStyle(.plain)
        } else {
            CoverCard(
                title: playlist.title,
                subtitle: playlist.kind.label,
                coverUrl: playlist.coverUrl,
                width: gridCoverWidth,
                symbol: "chart.bar"
            ) {
                toast.show("暂不支持该类型的歌单详情")
            }
        }
    }

    private func shufflePicks() {
        picks = Array(favorites.shuffled().prefix(6))
    }

    private func load() async {
        guard session.isAuthenticated else {
            playlists = []
            favorites = []
            picks = []
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            loadedOnce = true
        }
        do {
            async let discovered = MusicAPI.shared.discoverPlaylists()
            async let favoritesPage = MusicAPI.shared.favorites(start: 0, limit: 50)
            let (list, page) = try await (discovered, favoritesPage)
            playlists = list.playlists
            favorites = page.tracks
            shufflePicks()
        } catch {
            if !loadedOnce {
                toast.show(error.readableMessage)
            }
        }
    }
}

struct PlaylistsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var nav: NavState
    @EnvironmentObject private var toast: ToastCenter

    @State private var playlists: [Playlist] = []
    @State private var isLoading = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if playlists.isEmpty && !isLoading {
                    EmptyHint(title: "没有找到歌单", detail: "自建歌单和收藏歌单都会出现在这里。", systemImage: "rectangle.stack")
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(playlists) { playlist in
                        if playlist.kind == .owned || playlist.kind == .collected {
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist)
                            } label: {
                                CoverTile(
                                    title: playlist.title,
                                    subtitle: playlist.countLabel ?? playlist.kind.label,
                                    coverUrl: playlist.coverUrl,
                                    width: gridWidth,
                                    symbol: "music.note.list"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)
        }
        .background(Theme.bg)
        .navigationTitle("我的歌单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
    }

    private var gridWidth: CGFloat {
        let width = UIScreen.main.bounds.width - Theme.pagePadding * 2
        return max(120, (width - 12) / 2)
    }

    private func load() async {
        guard session.isAuthenticated else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            playlists = try await MusicAPI.shared.discoverPlaylists().playlists
        } catch {
            toast.show(error.readableMessage)
        }
    }
}

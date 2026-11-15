import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState
    @EnvironmentObject private var toast: ToastCenter

    @State private var query = ""
    @State private var tracks: [Track] = []
    @State private var total: Double?
    @State private var hasMore = false
    @State private var nextStart = 0
    @State private var isSearching = false
    @State private var pendingWork: Task<Void, Never>?

    @AppStorage("recent-queries") private var recentsRaw = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    recentsSection
                } else {
                    resultHeader
                    ForEach(tracks.indices, id: \.self) { index in
                        let track = tracks[index]
                        TrackRow(
                            track: track,
                            isCurrent: player.current?.id == track.id,
                            isPlaying: player.isPlaying
                        ) {
                            player.play(tracks, startIndex: index)
                        }
                        .trackActions(track)
                        .task {
                            if index >= tracks.count - 4, hasMore, !isSearching {
                                await performSearch(reset: false)
                            }
                        }
                    }
                    if isSearching {
                        ProgressView()
                            .tint(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    } else if tracks.isEmpty {
                        EmptyHint(title: "没有找到结果", detail: "换个关键词试试，曲库取决于账号所在区域。", systemImage: "magnifyingglass")
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .chromeScrollMargin()
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { searchBar }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: query) { newValue in
            scheduleSearch(for: newValue)
        }
        .onDisappear { pendingWork?.cancel() }
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faint)
                TextField("搜索歌曲", text: $query)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        pendingWork?.cancel()
                        Task { await performSearch(reset: true) }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        tracks = []
                        total = nil
                        hasMore = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.faint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            Button("取消") {
                query = ""
                nav.tab = nav.lastDockTab
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.muted)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.bg)
    }

    private var resultHeader: some View {
        HStack {
            Text(resultSummary)
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var resultSummary: String {
        if let total, total > 0 { return "约 \(Int(total)) 个结果" }
        return tracks.isEmpty ? "搜索中…" : "已加载 \(tracks.count) 首"
    }

    // MARK: - 最近搜索

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !recentQueries.isEmpty {
                HStack {
                    Text("最近搜索")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button("清空") {
                        recentsRaw = ""
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                }
                .padding(.top, 10)

                FlowChips(items: recentQueries) { item in
                    query = item
                    pendingWork?.cancel()
                    Task { await performSearch(reset: true) }
                }
            }
            EmptyHint(
                title: "搜一首歌开始听",
                detail: "搜索走在线曲库，不依赖账号；播放才需要登录。",
                systemImage: "magnifyingglass"
            )
        }
    }

    private var recentQueries: [String] {
        recentsRaw.split(separator: "\u{1F}").map(String.init)
    }

    private func remember(_ word: String) {
        var list = recentQueries.filter { $0 != word }
        list.insert(word, at: 0)
        recentsRaw = list.prefix(8).joined(separator: "\u{1F}")
    }

    // MARK: - 搜索

    private func scheduleSearch(for value: String) {
        pendingWork?.cancel()
        let word = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else {
            tracks = []
            total = nil
            hasMore = false
            isSearching = false
            return
        }
        pendingWork = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(reset: true)
        }
    }

    private func performSearch(reset: Bool) async {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        if isSearching { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await MusicAPI.shared.search(query: word, start: reset ? 0 : nextStart, limit: 20)
            if reset {
                tracks = page.tracks
                remember(word)
            } else {
                let existing = Set(tracks.map(\.id))
                tracks.append(contentsOf: page.tracks.filter { !existing.contains($0.id) })
            }
            nextStart = page.nextStart
            hasMore = page.hasMore
            total = page.total
        } catch {
            if !(error is CancellationError) {
                toast.show(error.readableMessage)
            }
        }
    }
}

/// 最近搜索的关键词胶囊，自动换行。
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Button {
                            onTap(item)
                        } label: {
                            Text(item)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Theme.surface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 简易分行：按字符宽度估算，每行最多 2 个，避免引入额外布局依赖。
    private var rows: [[String]] {
        stride(from: 0, to: items.count, by: 2).map { start in
            Array(items[start..<min(start + 2, items.count)])
        }
    }
}

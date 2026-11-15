import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case hall
    case search
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .hall: return "音乐厅"
        case .search: return "搜索"
        case .library: return "我的"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .hall: return "square.grid.2x2"
        case .search: return "magnifyingglass"
        case .library: return "person.crop.circle"
        }
    }

    /// 底部 dock 里显示的 Tab。搜索不进 dock，改由页面右上角的放大镜进入。
    static let dockTabs: [AppTab] = [.home, .hall, .library]

    var activeSymbol: String {
        switch self {
        case .home: return "house.fill"
        case .hall: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        case .library: return "person.crop.circle.fill"
        }
    }
}

/// 底部固定层：一块悬浮的迷你播放卡 + 一条悬浮的胶囊 Tab 栏。
///
/// 版式对齐 Apple Music（iOS 18/26 那一套）：内容从两者下方滚过去，
/// 两个控件都用玻璃材质浮在上面，不再像系统 TabBar 那样贴边、留一条硬分割线。
struct BottomChrome: View {
    @Binding var tab: AppTab

    /// 悬浮层占掉的高度，交给页面做底部留白。
    static let tabBarHeight: CGFloat = 62
    static let miniPlayerHeight: CGFloat = 60
    static let gap: CGFloat = 10
    static let bottomPadding: CGFloat = 4
    static let horizontalPadding: CGFloat = 12

    static func insetHeight(hasTrack: Bool) -> CGFloat {
        tabBarHeight + bottomPadding + 6 + (hasTrack ? miniPlayerHeight + gap : 0)
    }

    var body: some View {
        VStack(spacing: Self.gap) {
            MiniPlayerCard()
            FloatingTabBar(selection: $tab)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.bottom, Self.bottomPadding)
    }
}

// MARK: - 迷你播放卡

struct MiniPlayerCard: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Cover(url: track.coverUrl, size: 44, radius: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
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
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(height: BottomChrome.miniPlayerHeight)
            .chromeGlass(radius: 19)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .onTapGesture { nav.showPlayer = true }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

// MARK: - 顶部操作胶囊

/// 右上角那枚玻璃胶囊（对应 Apple Music 页头右侧的按钮组）。
/// 固定在页面右上角，内容从下面滚过，不参与滚动。
struct TopActionBar: View {
    @EnvironmentObject private var nav: NavState

    var body: some View {
        HStack(spacing: 0) {
            button("magnifyingglass") { nav.tab = .search }
            button("gearshape") { nav.showSettings = true }
        }
        .padding(.horizontal, 4)
        .frame(height: 40)
        .chromeGlass(radius: 20)
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text.opacity(0.92))
                .frame(width: 38, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 页面底部留白

private struct ChromeInset: View {
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        Color.clear
            .frame(height: BottomChrome.insetHeight(hasTrack: player.current != nil))
    }
}

extension View {
    /// 每个 Tab 的内容用它给悬浮层让位：内容会从玻璃下方滚过去，
    /// 但最后一行不会被挡住。
    func bottomChromeInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            ChromeInset()
        }
    }
}

// MARK: - 悬浮 Tab 栏

struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.dockTabs) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: BottomChrome.tabBarHeight)
        .chromeGlass(radius: BottomChrome.tabBarHeight / 2)
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            guard selection != tab else { return }
            selection = tab
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // 选中项的图标底下垫一块浅色块，对应 Apple Music 那种选中态。
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Theme.like.opacity(0.20) : Color.clear)
                        .frame(width: 48, height: 30)
                    Image(systemName: isSelected ? tab.activeSymbol : tab.symbol)
                        .font(.system(size: 20, weight: .medium))
                }
                .frame(height: 30)
                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Theme.like : Color.white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

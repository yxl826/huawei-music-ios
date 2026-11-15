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
    static let tabBarHeight: CGFloat = 58
    static let miniPlayerHeight: CGFloat = 62
    static let gap: CGFloat = 8
    static let bottomPadding: CGFloat = 6
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
                // 播放进度贴在卡片顶边，和 Apple Music 一样是一条极细的线。
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Color.clear
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: max(0, geometry.size.width * player.progress), height: 2)
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 1)

                HStack(spacing: 10) {
                    Cover(url: track.coverUrl, size: 42, radius: 7)
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
                .padding(.top, 5)
                .padding(.bottom, 7)
            }
            .frame(height: BottomChrome.miniPlayerHeight)
            .glass(radius: 17, tint: 0.06, shadow: true)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .onTapGesture { nav.showPlayer = true }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
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
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: BottomChrome.tabBarHeight)
        .glass(radius: BottomChrome.tabBarHeight / 2, tint: 0.05, shadow: true)
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            guard selection != tab else { return }
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.activeSymbol : tab.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(height: 20)
                Text(tab.title)
                    .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Theme.like : Color.white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

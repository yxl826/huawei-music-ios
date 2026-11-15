import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case hall
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .hall: return "音乐厅"
        case .library: return "我的"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .hall: return "square.grid.2x2"
        case .library: return "person.crop.circle"
        }
    }

    var activeSymbol: String {
        switch self {
        case .home: return "house.fill"
        case .hall: return "square.grid.2x2.fill"
        case .library: return "person.crop.circle.fill"
        }
    }
}

/// 迷你播放条：浮在系统 TabBar 上方的一张卡片。
///
/// 底部 TabBar 交还给系统（`TabView` + `.tabItem`）：iOS 26 的系统 TabBar 自带
/// Liquid Glass、选中态滑动和按住拖动，手写永远差一截。这里只负责上面那张卡片。
struct MiniPlayerCard: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState

    static let height: CGFloat = 60
    /// 卡片底部与 TabBar 之间的空隙，滚动内容的底部留白按它算。
    static let bottomGap: CGFloat = 6
    static let sideGap: CGFloat = 12

    var body: some View {
        if let track = player.current {
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
            .frame(height: Self.height)
            .glass(radius: 18, tint: 0.06, shadow: true)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture { nav.showPlayer = true }
            .padding(.horizontal, Self.sideGap)
            .padding(.bottom, Self.bottomGap)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

// MARK: - 顶部操作胶囊

/// 右上角那枚玻璃胶囊（对应 Apple Music 页头右侧的按钮组）。
struct TopActionBar: View {
    @EnvironmentObject private var nav: NavState

    var body: some View {
        HStack(spacing: 0) {
            button("magnifyingglass") { nav.showSearch = true }
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

extension View {
    /// 每个 Tab 的根视图挂上它：迷你播放卡浮在底部，内容从卡片下面滚过去。
    func miniPlayerOverlay() -> some View {
        overlay(alignment: .bottom) {
            MiniPlayerCard()
        }
    }

    /// 给滚动内容加底部留白，而不是把滚动视图整个缩短。
    ///
    /// 用 safeAreaInset 时内容停在悬浮层上方，玻璃底下永远是一片纯色，看着就像「没有玻璃」；
    /// 改成 contentMargins 后内容会从卡片下面滚过去，玻璃才有东西可以模糊。
    func chromeScrollMargin() -> some View {
        modifier(ChromeScrollMargin())
    }
}

private struct ChromeScrollMargin: ViewModifier {
    @EnvironmentObject private var player: PlayerEngine

    @ViewBuilder
    func body(content: Content) -> some View {
        let height = player.current == nil ? 0 : MiniPlayerCard.height + MiniPlayerCard.bottomGap + 8
        if #available(iOS 17.0, *) {
            content.contentMargins(.bottom, height, for: .scrollContent)
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: height)
            }
        }
    }
}

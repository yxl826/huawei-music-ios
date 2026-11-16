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
                    Haptics.thump()
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
                    Haptics.tap()
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

// MARK: - 迷你播放条（iOS 26 系统底部附属视图）

/// iOS 26 的 `tabViewBottomAccessory` 只负责放内容：外面的玻璃容器由系统按 TabBar 的
/// 尺寸和圆角绘制，宽度与 dock 完全对齐（Apple Music 就是这么做的）。
/// 所以这里不要再自己加背景、圆角或左右留白——加了就会比 dock 宽出一截。
struct MiniPlayerAccessory: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState

    var body: some View {
        if let track = player.current {
            HStack(spacing: 10) {
                Cover(url: track.coverUrl, size: 38, radius: 7)
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
                    Haptics.thump()
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.tap()
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
            .onTapGesture { nav.showPlayer = true }
        }
    }
}

extension View {
    /// iOS 26：把迷你播放条挂成 TabView 的底部附属视图，由系统负责与 dock 对齐。
    /// 更早的系统什么都不做，交给 `miniPlayerOverlay()` 画那张浮动卡片。
    @ViewBuilder
    func miniPlayerAccessory() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            tabViewBottomAccessory {
                MiniPlayerAccessory()
            }
        } else {
            self
        }
        #else
        self
        #endif
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
        Button {
            Haptics.tap()
            action()
        } label: {
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
    /// iOS 26 及以上不挂：那边由 `tabViewBottomAccessory` 接管，重复挂会叠出两层。
    @ViewBuilder
    func miniPlayerOverlayIfNeeded() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self
        } else {
            miniPlayerOverlay()
        }
        #else
        miniPlayerOverlay()
        #endif
    }

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
        // iOS 26 的底部附属视图本身就占掉了 TabBar 上方的高度，系统会自动给内容留位；
        // 这里只补一点点呼吸空间，再叠一整张卡片的高度就会出现一大片空白。
        if #available(iOS 17.0, *) {
            content.contentMargins(.bottom, bottomMargin, for: .scrollContent)
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomMargin)
            }
        }
    }

    private var bottomMargin: CGFloat {
        guard player.current != nil else { return 0 }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            return 8
        }
        #endif
        return MiniPlayerCard.height + MiniPlayerCard.bottomGap + 8
    }
}

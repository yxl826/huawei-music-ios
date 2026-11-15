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
        case .library: return "person"
        }
    }

    var activeSymbol: String {
        switch self {
        case .home: return "house.fill"
        case .hall: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        case .library: return "person.fill"
        }
    }
}

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.08))
                        Rectangle()
                            .fill(Theme.text.opacity(0.55))
                            .frame(width: geometry.size.width * player.progress)
                    }
                }
                .frame(height: 2)

                HStack(spacing: 10) {
                    Cover(url: track.coverUrl, size: 38, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(track.artistLine)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 36, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .background(Theme.surface)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { nav.showPlayer = true }
        }
    }
}

extension View {
    /// 每个 Tab 的内容都用它把迷你播放条顶在系统 TabBar 上方。
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer()
        }
    }
}

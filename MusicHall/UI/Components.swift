import SwiftUI
import UIKit

// MARK: - 封面

struct RemoteImage: View {
    let url: String?
    var placeholderSymbol: String = "music.note"

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.surface2
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.faint)
            }
        }
        .task(id: url) {
            guard let url, image == nil else { return }
            image = await CoverCache.shared.image(for: url)
        }
    }
}

struct Cover: View {
    let url: String?
    var size: CGFloat
    var radius: CGFloat = 8
    var symbol: String = "music.note"

    var body: some View {
        RemoteImage(url: url, placeholderSymbol: symbol)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - 行

struct TrackRow: View {
    let track: Track
    var isCurrent: Bool = false
    var isPlaying: Bool = false
    var showsCover: Bool = true
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if showsCover {
                    Cover(url: track.coverUrl, size: 46, radius: 8)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isCurrent ? Theme.like : Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if isCurrent {
                            Image(systemName: isPlaying ? "waveform" : "pause.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.like)
                        }
                        Text(track.artistLine)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Text(track.durationLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 标题与按钮

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

struct PillButton: View {
    let title: String
    var systemImage: String?
    var filled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(filled ? Theme.bg : Theme.text)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(filled ? Theme.primary : Theme.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CircleIconButton: View {
    let symbol: String
    var size: CGFloat = 40
    var active: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(active ? Theme.like : Theme.text)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 进度条

struct ScrubBar: View {
    var value: Double
    var onSeek: (Double) -> Void

    @State private var dragging: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let fraction = min(1, max(0, dragging ?? value))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 3)
                Capsule()
                    .fill(Theme.text)
                    .frame(width: width * fraction, height: 3)
                Circle()
                    .fill(Theme.text)
                    .frame(width: dragging == nil ? 9 : 15, height: dragging == nil ? 9 : 15)
                    .offset(x: max(0, width * fraction - (dragging == nil ? 4.5 : 7.5)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = min(1, max(0, gesture.location.x / width))
                    }
                    .onEnded { _ in
                        if let target = dragging {
                            onSeek(target)
                        }
                        dragging = nil
                    }
            )
        }
        .frame(height: 24)
    }
}

// MARK: - 空态

struct EmptyHint: View {
    let title: String
    var detail: String?
    var systemImage: String = "sparkles"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.faint)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

// MARK: - 轻提示

@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var message: String?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String) {
        message = text
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

// MARK: - 长按菜单

struct TrackActionsModifier: ViewModifier {
    let track: Track
    var unfavorite: (() -> Void)?
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var toast: ToastCenter

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                player.play([track], startIndex: 0)
            } label: {
                Label("立即播放", systemImage: "play.fill")
            }
            Button {
                player.enqueueNext([track])
                toast.show("已插入下一首")
            } label: {
                Label("下一首播放", systemImage: "text.insert")
            }
            Button {
                player.enqueueLast([track])
                toast.show("已加入播放队列")
            } label: {
                Label("添加到播放队列", systemImage: "text.append")
            }
            if let unfavorite {
                Divider()
                Button(role: .destructive, action: unfavorite) {
                    Label("取消收藏", systemImage: "heart.slash")
                }
            }
        }
    }
}

extension View {
    func trackActions(_ track: Track, unfavorite: (() -> Void)? = nil) -> some View {
        modifier(TrackActionsModifier(track: track, unfavorite: unfavorite))
    }
}

// MARK: - 卡片

/// 纯版式，不含点击：给 NavigationLink 或外层手势复用，避免按钮套按钮。
struct CoverTile: View {
    let title: String
    var subtitle: String?
    var coverUrl: String?
    var width: CGFloat = 116
    var symbol: String = "music.note"

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RemoteImage(url: coverUrl, placeholderSymbol: symbol)
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct CoverCard: View {
    let title: String
    var subtitle: String?
    var coverUrl: String?
    var width: CGFloat = 116
    var symbol: String = "music.note"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            CoverTile(title: title, subtitle: subtitle, coverUrl: coverUrl, width: width, symbol: symbol)
        }
        .buttonStyle(.plain)
    }
}

/// 未登录时挡在个性化内容前面的提示卡。
struct LoginPrompt: View {
    let title: String
    let detail: String
    let onLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            PillButton(title: "登录华为账号", systemImage: "person.crop.circle", action: onLogin)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel(radius: Theme.radiusXL)
    }
}

/// 大标题 + 一行说明，替代系统的 navigationTitle（本应用自绘页头）。
struct PageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


import SwiftUI
import UIKit

/// 播放页：按 Apple Music 的「正在播放」版式重做。
///
/// 结构自上而下：抓手 + 顶部信息条（封面缩略图 / 歌名歌手 / 收藏 / 收起）
/// → 歌词（或大封面）→ 进度与时间 → 上一首 / 播放 / 下一首 → 底部三个功能图标。
///
/// 宽度全部由窗口宽度显式给出：歌词内容再长也不能把页面撑宽，
/// 否则整页会被居中裁切、顶栏按钮被挤到屏幕外（1.2.0 那个「进得去出不来」就是这个问题）。
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState

    @State private var page: Page = .lyrics
    @State private var dragOffset: CGFloat = 0

    private let sidePadding: CGFloat = 20

    enum Page {
        case lyrics
        case cover
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                ArtworkBackdrop(url: player.current?.coverUrl)

                if let track = player.current {
                    content(track, width: width)
                } else {
                    EmptyHint(
                        title: "还没有在播放的歌",
                        detail: "从收藏、歌单或搜索里点一首开始。",
                        systemImage: "play.circle"
                    )
                    .padding(.horizontal, 30)
                }
            }
            .frame(width: width, height: geometry.size.height)
            .clipped()
        }
        .preferredColorScheme(.dark)
        .offset(y: dragOffset)
        .sheet(isPresented: $nav.showQueue) {
            QueueSheet()
        }
    }

    // MARK: - 整体

    private func content(_ track: Track, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            grabber
                .padding(.top, 4)

            header(track)
                .padding(.top, 12)

            pageBody(track, width: max(0, width - sidePadding * 2))
                .frame(maxHeight: .infinity)

            progressBlock
                .padding(.top, 6)

            transportRow
                .padding(.top, 14)

            bottomRow
                .padding(.top, 14)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, sidePadding)
        .frame(width: width)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.white.opacity(0.28))
            .frame(width: 36, height: 5)
    }

    /// 只在抓手与信息条上识别下拉，避免和歌词滚动、进度拖动抢手势。
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                dragOffset = value.translation.height * 0.6
            }
            .onEnded { value in
                if value.translation.height > 90 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - 顶部信息条

    private func header(_ track: Track) -> some View {
        HStack(spacing: 12) {
            ArtworkImage(url: track.coverUrl)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)
                Text(qualityLine(track))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                player.toggleFavorite()
            } label: {
                Image(systemName: player.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(player.isFavorite ? Theme.like : Color.white.opacity(0.88))
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .gesture(dismissGesture)
    }

    private func qualityLine(_ track: Track) -> String {
        var parts: [String] = [track.artistLine]
        switch player.actualQuality {
        case Quality.lossless.rawValue: parts.append("无损")
        case Quality.standard.rawValue: parts.append("标准")
        default: break
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 主体

    @ViewBuilder
    private func pageBody(_ track: Track, width: CGFloat) -> some View {
        ZStack {
            if page == .lyrics {
                lyricsPage(width: width)
                    .transition(.opacity)
            } else {
                coverPage(track, width: width)
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .frame(width: width)
    }

    @ViewBuilder
    private func lyricsPage(width: CGFloat) -> some View {
        if !player.lyrics.lines.isEmpty {
            LyricsPane(
                lines: player.lyrics.lines,
                activeIndex: LyricsParser.activeIndex(
                    player.lyrics.lines,
                    positionMs: player.position * 1000
                ),
                width: width
            ) { seconds in
                player.seek(to: seconds)
                if !player.isPlaying { player.togglePlayPause() }
            }
        } else {
            VStack(spacing: 12) {
                if player.isLoadingLyrics {
                    ProgressView().tint(Color.white.opacity(0.6))
                    Text("正在取歌词…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                } else {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text("这首歌没有可显示的歌词")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                    if !player.lyricsNote.isEmpty {
                        Text(player.lyricsNote)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.38))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 26)
                    }
                    Button {
                        player.reloadLyrics()
                    } label: {
                        Text("重新加载")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .chromeGlass(radius: 16)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .frame(width: width, height: 360)
        }
    }

    private func coverPage(_ track: Track, width: CGFloat) -> some View {
        VStack {
            Spacer(minLength: 0)
            ArtworkImage(url: track.coverUrl)
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.55), radius: 30, y: 18)
                .scaleEffect(player.isPlaying ? 1 : 0.94)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: player.isPlaying)
            Spacer(minLength: 0)
        }
        .frame(width: width)
    }

    // MARK: - 进度

    private var progressBlock: some View {
        VStack(spacing: 4) {
            ScrubBar(value: player.progress) { fraction in
                guard player.duration > 0 else { return }
                player.seek(to: player.duration * fraction)
            }

            HStack {
                Text(timeLabel(player.position))
                Spacer(minLength: 8)
                Text("-" + timeLabel(max(0, player.duration - player.position)))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.45))
        }
    }

    // MARK: - 传输控制

    private var transportRow: some View {
        HStack(spacing: 0) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 64, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(Color.white)
                    if player.isBuffering && player.isPlaying {
                        ProgressView().tint(Color.black).scaleEffect(0.85)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.black)
                            .offset(x: player.isPlaying ? 0 : 1.5)
                    }
                }
                .frame(width: 58, height: 58)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 64, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - 底部功能行

    private var bottomRow: some View {
        HStack {
            iconButton(player.mode.symbol) {
                player.cycleMode()
            }
            Spacer(minLength: 0)
            iconButton(page == .lyrics ? "photo" : "quote.bubble") {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    page = (page == .lyrics ? .cover : .lyrics)
                }
            }
            Spacer(minLength: 0)
            iconButton("list.bullet") {
                nav.showQueue = true
            }
        }
        .padding(.horizontal, 22)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 歌词正文

private struct LyricsPane: View {
    let lines: [LyricsLine]
    let activeIndex: Int
    /// 由播放页显式传入：不接受 ScrollView 自己的宽度推导，避免内容撑宽页面。
    let width: CGFloat
    let onSeek: (Double) -> Void

    /// 手动滑动歌词后短暂停止自动跟随，否则手指还没松就开始被拽回当前行。
    @State private var manualScrollingUntil: Date = .distantPast

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 88)
                    ForEach(lines.indices, id: \.self) { index in
                        row(index)
                    }
                    Color.clear.frame(height: 140)
                }
                .frame(width: width, alignment: .leading)
            }
            .frame(width: width)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.14),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { _ in
                        manualScrollingUntil = Date().addingTimeInterval(2.5)
                    }
            )
            .onChange(of: activeIndex) { value in
                guard value >= 0, Date() >= manualScrollingUntil else { return }
                withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
            .onAppear {
                guard activeIndex > 0 else { return }
                proxy.scrollTo(activeIndex, anchor: .center)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let line = lines[index]
        let isActive = index == activeIndex
        let distance = abs(index - activeIndex)
        let opacity: Double = {
            guard activeIndex >= 0 else { return 0.55 }
            if isActive { return 1 }
            // 离当前行越远越淡，接近 Apple Music 那种「聚光」感。
            return max(0.16, 0.60 - Double(distance) * 0.11)
        }()

        return VStack(alignment: .leading, spacing: 4) {
            Text(line.text)
                .font(.system(size: isActive ? 25 : 21, weight: isActive ? .bold : .regular))
                .foregroundStyle(Color.white.opacity(opacity))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
            if let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: isActive ? 15 : 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isActive ? 0.7 : 0.28))
                    .multilineTextAlignment(.leading)
                    .frame(width: width, alignment: .leading)
            }
        }
        .frame(width: width, alignment: .leading)
        .id(index)
        .contentShape(Rectangle())
        .onTapGesture {
            if let timeMs = line.timeMs {
                onSeek(timeMs / 1000)
            }
        }
    }
}

// MARK: - 背景与封面

private struct ArtworkBackdrop: View {
    let url: String?

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.bg
            if let image {
                // 这里放的是一张 64×64 的预模糊小图，放大后本身就是模糊的。
                // 不再对整屏图做实时 .blur(radius: 68) —— 那是之前异常发热的主因。
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(1.35)
                    .opacity(0.66)
            }
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.16), location: 0),
                    .init(color: Color.black.opacity(0.52), location: 0.46),
                    .init(color: Color.black.opacity(0.88), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url, !url.isEmpty else {
            image = nil
            return
        }
        image = await CoverCache.shared.backdrop(for: url)
    }
}

private struct ArtworkImage: View {
    let url: String?

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Theme.surface2, Theme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.16))
            }
        }
        .clipped()
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url, !url.isEmpty else {
            image = nil
            return
        }
        if let hit = CoverCache.shared.cached(url) {
            image = hit
            return
        }
        image = await CoverCache.shared.image(for: url)
    }
}

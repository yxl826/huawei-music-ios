import SwiftUI
import UIKit

/// 播放页：Apple Music 那种「歌词当主角」的版式。
///
/// 背景是封面重模糊 + 三层渐变压暗，顶栏和底部控制条用玻璃材质
/// （iOS 26 起走系统 Liquid Glass，更早的系统用超薄材质近似）；
/// 歌词左对齐、当前行加粗放大、点行跳转、随播放自动居中。
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState

    @State private var page: Page = .lyrics
    @State private var dragOffset: CGFloat = 0

    enum Page {
        case lyrics
        case cover
    }

    var body: some View {
        ZStack {
            ArtworkBackdrop(url: player.current?.coverUrl)

            if let track = player.current {
                VStack(spacing: 0) {
                    topBar(track)
                    pageBody(track)
                    transport
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
            } else {
                EmptyHint(
                    title: "还没有在播放的歌",
                    detail: "从收藏、歌单或搜索里点一首开始。",
                    systemImage: "play.circle"
                )
                .padding(.horizontal, 30)
            }
        }
        .preferredColorScheme(.dark)
        .offset(y: dragOffset)
        .sheet(isPresented: $nav.showQueue) {
            QueueSheet()
        }
    }

    // MARK: - 顶栏

    private func topBar(_ track: Track) -> some View {
        HStack(spacing: 10) {
            GlassCircleButton(systemName: "chevron.down") {
                dismiss()
            }

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text(track.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                Text(qualityLine(track))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(maxWidth: 190)

            Spacer(minLength: 8)

            GlassCircleButton(systemName: page == .lyrics ? "music.note" : "quote.bubble") {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    page = (page == .lyrics ? .cover : .lyrics)
                }
            }

            GlassCircleButton(systemName: "list.bullet") {
                nav.showQueue = true
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
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
    private func pageBody(_ track: Track) -> some View {
        ZStack {
            if page == .lyrics {
                lyricsPage
                    .transition(.opacity)
            } else {
                coverPage(track)
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 歌词页

    @ViewBuilder
    private var lyricsPage: some View {
        if !player.lyrics.lines.isEmpty {
            LyricsPane(
                lines: player.lyrics.lines,
                activeIndex: LyricsParser.activeIndex(
                    player.lyrics.lines,
                    positionMs: player.position * 1000
                )
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
                            .glass(radius: 16, tint: 0.07)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 封面页

    private func coverPage(_ track: Track) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 6)

            ArtworkImage(url: track.coverUrl)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.55), radius: 32, y: 20)
                .scaleEffect(player.isPlaying ? 1 : 0.93)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: player.isPlaying)

            Spacer(minLength: 18)

            VStack(spacing: 5) {
                Text(track.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(track.artistLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                if let album = track.album?.title, !album.isEmpty {
                    Text(album)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.32))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 10)
        }
        .gesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    dragOffset = max(0, value.translation.height * 0.5)
                }
                .onEnded { value in
                    if value.translation.height > 110 {
                        dismiss()
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                }
        )
    }

    // MARK: - 底部控制条

    private var transport: some View {
        VStack(spacing: 7) {
            ScrubBar(value: player.progress) { fraction in
                guard player.duration > 0 else { return }
                player.seek(to: player.duration * fraction)
            }

            HStack {
                Text(timeLabel(player.position))
                Spacer(minLength: 8)
                Text("-" + timeLabel(max(0, player.duration - player.position)))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.42))

            HStack(spacing: 0) {
                Button {
                    player.cycleMode()
                } label: {
                    Image(systemName: player.mode.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    player.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(width: 52, height: 52)
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
                            ProgressView().tint(Color.black).scaleEffect(0.8)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Color.black)
                                .offset(x: player.isPlaying ? 0 : 1)
                        }
                    }
                    .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    player.toggleFavorite()
                } label: {
                    Image(systemName: player.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(player.isFavorite ? Theme.like : Color.white.opacity(0.62))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .glass(radius: 30, tint: 0.06)
        .padding(.top, 8)
        .padding(.bottom, 2)
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
    let onSeek: (Double) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 46)
                    ForEach(lines.indices, id: \.self) { index in
                        row(index)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.10),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: activeIndex) { value in
                guard value >= 0 else { return }
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
        return VStack(alignment: .leading, spacing: 5) {
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: isActive ? 27 : 23, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.38))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: isActive ? 15 : 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isActive ? 0.7 : 0.28))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.system(size: 38, weight: .light))
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

// MARK: - 玻璃圆钮

private struct GlassCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.86))
                .frame(width: 34, height: 34)
                .glass(radius: 17, tint: 0.07)
        }
        .buttonStyle(.plain)
    }
}

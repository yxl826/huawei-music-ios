import SwiftUI
import UIKit

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var nav: NavState

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                if let track = player.current {
                    Spacer(minLength: 2)
                    cover(track)
                    infoArea(track)
                    lyricsArea
                        .frame(maxHeight: .infinity)
                    progressArea
                    controls
                    Spacer(minLength: 2)
                } else {
                    Spacer()
                    EmptyHint(title: "还没有在播放的歌", detail: "从收藏、歌单或搜索里点一首开始。", systemImage: "play.circle")
                    Spacer()
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .offset(y: dragOffset)
        .sheet(isPresented: $nav.showQueue) {
            QueueSheet()
        }
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            Theme.bg
            RadialGradient(
                colors: [Theme.surface2.opacity(0.95), Theme.bg],
                center: .top,
                startRadius: 40,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 3) {
                Text("正在播放")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.faint)
                if let badge = qualityBadge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(Theme.lineStrong, lineWidth: 1))
                }
            }

            Spacer()

            Button {
                nav.showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var qualityBadge: String? {
        switch player.actualQuality {
        case Quality.lossless.rawValue: return "无损 FLAC"
        case Quality.standard.rawValue: return "标准 MP3"
        default: return nil
        }
    }

    // MARK: - 封面

    private var coverSide: CGFloat {
        let screen = UIScreen.main.bounds
        return min(screen.width - 44, max(150, screen.height * 0.30))
    }

    private func cover(_ track: Track) -> some View {
        Cover(url: track.coverUrl, size: coverSide, radius: 18)
            .shadow(color: Color.black.opacity(0.45), radius: 26, y: 14)
            .scaleEffect(player.isPlaying ? 1 : 0.94)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: player.isPlaying)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = max(0, value.translation.height * 0.35)
                    }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            dismiss()
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            dragOffset = 0
                        }
                    }
            )
    }

    // MARK: - 曲目信息

    private func infoArea(_ track: Track) -> some View {
        VStack(spacing: 5) {
            Text(track.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            HStack(spacing: 5) {
                Text(track.artistLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if let album = track.album?.title, !album.isEmpty {
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faint)
                    Text(album)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: - 歌词

    @ViewBuilder
    private var lyricsArea: some View {
        if player.lyrics.lines.isEmpty {
            VStack {
                if player.isLoadingLyrics {
                    ProgressView().tint(Theme.muted)
                } else {
                    Text("这首歌暂时没有歌词")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70, maxHeight: .infinity)
        } else {
            LyricsView(
                lines: player.lyrics.lines,
                activeIndex: LyricsParser.activeIndex(
                    player.lyrics.lines,
                    positionMs: player.position * 1000
                )
            ) { seconds in
                player.seek(to: seconds)
            }
        }
    }

    // MARK: - 进度

    private var progressArea: some View {
        VStack(spacing: 2) {
            ScrubBar(value: player.progress) { fraction in
                guard player.duration > 0 else { return }
                player.seek(to: player.duration * fraction)
            }
            HStack {
                Text(timeLabel(player.position))
                Spacer()
                Text(timeLabel(player.duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Theme.faint)
        }
        .padding(.top, 4)
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - 控制

    private var controls: some View {
        HStack(spacing: 0) {
            Button {
                player.cycleMode()
            } label: {
                Image(systemName: player.mode.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 54, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(Theme.primary)
                    if player.isBuffering && player.isPlaying {
                        ProgressView().tint(Theme.bg).scaleEffect(0.8)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.bg)
                    }
                }
                .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 54, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                player.toggleFavorite()
            } label: {
                Image(systemName: player.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(player.isFavorite ? Theme.like : Theme.muted)
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }
}

struct LyricsView: View {
    let lines: [LyricsLine]
    let activeIndex: Int
    let onSeek: (Double) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 13) {
                    ForEach(lines.indices, id: \.self) { index in
                        let line = lines[index]
                        VStack(spacing: 2) {
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: index == activeIndex ? 15 : 13,
                                              weight: index == activeIndex ? .semibold : .regular))
                                .foregroundStyle(index == activeIndex ? Theme.text : Theme.faint)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            if let translation = line.translation, !translation.isEmpty {
                                Text(translation)
                                    .font(.system(size: 11))
                                    .foregroundStyle(index == activeIndex ? Theme.muted : Theme.faint.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .id(index)
                        .onTapGesture {
                            if let timeMs = line.timeMs {
                                onSeek(timeMs / 1000)
                            }
                        }
                    }
                }
                .padding(.vertical, 60)
            }
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
            .onChange(of: activeIndex) { value in
                guard value >= 0 else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
        }
    }
}

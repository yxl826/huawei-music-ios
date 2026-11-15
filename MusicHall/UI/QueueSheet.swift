import SwiftUI

struct QueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Rectangle().fill(Theme.line).frame(height: 1)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let current = player.current {
                            VStack(alignment: .leading, spacing: 8) {
                                label("正在播放")
                                QueueRow(
                                    track: current,
                                    isCurrent: true,
                                    isPlaying: player.isPlaying,
                                    onTap: {},
                                    onRemove: nil
                                )
                            }
                        }

                        let upcoming = upcomingTracks
                        if !upcoming.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    label("接下来 · \(upcoming.count) 首")
                                    Spacer()
                                    Button {
                                        player.clearUpcoming()
                                    } label: {
                                        Text("清空待播")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Theme.muted)
                                    }
                                    .buttonStyle(.plain)
                                }
                                ForEach(upcoming) { item in
                                    QueueRow(
                                        track: item.track,
                                        isCurrent: false,
                                        isPlaying: player.isPlaying,
                                        onTap: { player.jump(to: item.id) },
                                        onRemove: { player.remove(at: item.id) }
                                    )
                                }
                            }
                        } else if player.current == nil {
                            EmptyHint(title: "播放队列是空的", detail: "从收藏、歌单或搜索里点一首开始。", systemImage: "list.bullet")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var upcomingTracks: [QueueEntry] {
        guard player.index >= 0, player.index + 1 < player.queue.count else { return [] }
        return ((player.index + 1)..<player.queue.count).map { index in
            QueueEntry(id: index, track: player.queue[index])
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("播放队列")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("共 \(player.queue.count) 首")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30, height: 30)
                    .background(Theme.surface2, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.faint)
    }
}

private struct QueueEntry: Identifiable {
    let id: Int
    let track: Track
}

private struct QueueRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Cover(url: track.coverUrl, size: 38, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isCurrent ? Theme.like : Theme.text)
                            .lineLimit(1)
                        Text(track.artistLine)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if isCurrent {
                Image(systemName: isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.like)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.vertical, 4)
    }
}

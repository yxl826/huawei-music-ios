import ActivityKit
import SwiftUI
import WidgetKit

/// 锁屏 / 通知中心里的歌词卡片，外加灵动岛的紧凑与展开态。
struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LockScreenLyrics(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.62))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timeLabel(context.state.position))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.currentLine.isEmpty ? "♪" : context.state.currentLine)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let next = context.state.nextLine, !next.isEmpty {
                            Text(next)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            } compactTrailing: {
                // 紧凑态放不下整句，用进度条表示这首歌走到哪了。
                ProgressView(value: progress(context.state))
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 34)
            } minimal: {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .keylineTint(.white)
        }
    }

    private func progress(_ state: LyricsActivityAttributes.ContentState) -> Double {
        guard state.duration > 0 else { return 0 }
        return min(1, max(0, state.position / state.duration))
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 锁屏那张卡：歌名一行、当前这句大字、下一句预告。
private struct LockScreenLyrics: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: state.isPlaying ? "music.note" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(state.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                Text(state.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(timeLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text(state.currentLine.isEmpty ? "♪" : state.currentLine)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let next = state.nextLine, !next.isEmpty {
                Text(next)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var timeLabel: String {
        guard state.position.isFinite, state.position >= 0 else { return "0:00" }
        let total = Int(state.position.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

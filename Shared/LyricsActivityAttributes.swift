import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// 锁屏 / 通知中心的那块「正在播放的歌词」卡片。
///
/// 系统自带的播控组件只认 MPMediaItem 里固定的那几个字段（标题、歌手、封面……），
/// 歌词不在白名单里，`MPMediaItemPropertyLyrics` 写进去也不会显示。
/// 想在通知中心看到歌词，只有一条路：Live Activity。
///
/// 这个文件同时被主 App 与 Widget 扩展编译：App 负责 start / update / end，
/// 扩展负责画。两边必须用同一份类型定义，所以放在 Shared 下。
@available(iOS 16.1, *)
struct LyricsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        /// 当前这一句。没有歌词时给空串。
        var currentLine: String
        /// 下一句，用来做「下一句预告」的暗色小字。
        var nextLine: String?
        var isPlaying: Bool
        var position: Double
        var duration: Double
    }

    var trackId: String
}
#endif

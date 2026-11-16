import SwiftUI
import WidgetKit

/// Widget 扩展的入口。现在只有一块 Live Activity，没有桌面小组件。
@main
struct MusicHallWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
    }
}

import UIKit

/// 轻触感反馈。
///
/// 生成器只建一次并常驻：每次临时 `UIImpactFeedbackGenerator()` 都要重新预热，
/// 连点时会漏掉第一下。
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let selection = UISelectionFeedbackGenerator()

    /// 普通点按：切页、收藏、图标按钮。
    static func tap() {
        light.impactOccurred()
        light.prepare()
    }

    /// 稍重一点：播放 / 暂停 / 切歌。
    static func thump() {
        medium.impactOccurred()
        medium.prepare()
    }

    /// 极轻的「咔」：拖进度条、拨到下一格。
    static func tick() {
        selection.selectionChanged()
        selection.prepare()
    }
}

import SwiftUI

/// 设计令牌：与桌面版保持同一套颜色关系（近黑底 + 一个红心色，颜色只留给封面）。
enum Theme {
    static let bg = Color(hex: 0x0A0A0C)
    static let surface = Color(hex: 0x141418)
    static let surface2 = Color(hex: 0x1B1B21)
    static let surface3 = Color(hex: 0x232329)
    static let line = Color.white.opacity(0.07)
    static let lineStrong = Color.white.opacity(0.13)
    static let text = Color(hex: 0xF2F2F5)
    static let muted = Color(hex: 0x9A9AA5)
    static let faint = Color(hex: 0x62626D)
    static let like = Color(hex: 0xFF375F)
    static let primary = Color(hex: 0xF4F4F6)

    static let radiusXL: CGFloat = 20
    static let radiusLG: CGFloat = 14
    static let radiusMD: CGFloat = 10
    static let radiusSM: CGFloat = 7

    static let pagePadding: CGFloat = 18
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

extension View {
    /// 卡片：深色底 + 一层极淡描边，模仿桌面版的浮层关系。
    func panel(radius: CGFloat = Theme.radiusLG) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }

    /// 玻璃质感。iOS 26 起直接用系统的 Liquid Glass；iOS 16–18 用超薄材质 +
    /// 高光描边 + 投影近似（观感接近，但不是系统那层折射）。
    func glass(radius: CGFloat = 22, tint: Double = 0.05) -> some View {
        modifier(GlassSurface(radius: radius, tint: tint))
    }
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat = 22
    var tint: Double = 0.05

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            approximating(content)
        }
        #else
        approximating(content)
        #endif
    }

    @ViewBuilder
    private func approximating(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.white.opacity(tint))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.34),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.35), radius: 20, y: 8)
    }
}

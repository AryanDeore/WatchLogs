import SwiftUI

// Ports the CSS custom properties from prototypes/menubar-layout/index.html
// 1:1 so the two prototypes render as close to identically as HTML and
// SwiftUI allow. Keep these in sync if the HTML palette changes.
enum Theme {
    static let ink = Color(hex: 0x1d1f24)
    static let inkDim = Color(hex: 0x6b7280)
    static let inkFaint = Color(hex: 0x9aa1ad)
    static let panel = Color(hex: 0xf7f8fa)
    static let panel2 = Color(hex: 0xeef0f4)
    static let card = Color.white
    static let line = Color(hex: 0xe2e5ea)
    static let line2 = Color(hex: 0xd3d7de)
    static let accent = Color(hex: 0x3b6ef5)
    static let accentSoft = Color(hex: 0xe8effe)
    static let good = Color(hex: 0x128a5b)
    static let warn = Color(hex: 0xa8630b)
    static let warnSoft = Color(hex: 0xfbeedd)

    // .tag.fmt / .tag.emb / .tag.live
    static let fmtTagBg = Color(hex: 0xe9eefb)
    static let fmtTagFg = Color(hex: 0x2c4c9c)
    static let liveTagBg = Color(hex: 0xfdece8)

    // Viz palette — departs from brand so stacked bars stay legible
    // (YouTube and Netflix are both red in reality).
    static let yt = Color(hex: 0xe5342b)
    static let nflx = Color(hex: 0xe0902f)
    static let twitch = Color(hex: 0x7a5cff)
    static let other = Color(hex: 0x9aa1ad)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }
}

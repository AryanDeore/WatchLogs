import SwiftUI

// The shipped menu-bar mark, copied verbatim from `prototypes/app-logo-concepts`
// (Concept A, `LogPlayMark`) so this prototype is self-contained. Three
// horizontal bars whose right edges step outward to a peak: reads as a list of
// log entries and as a play triangle. This is the icon the user said they want
// to keep; every variant here pairs it (or deliberately drops it) with a
// running watched-time readout.
struct LogPlayMark: View {
    var size: CGFloat = 120
    var color: Color = .primary

    private let barHeightFraction: CGFloat = 0.15
    private let leftInsetFraction: CGFloat = 0.24

    var body: some View {
        ZStack {
            bar(widthFraction: 0.26, yFraction: 0.28)
            bar(widthFraction: 0.52, yFraction: 0.50)
            bar(widthFraction: 0.26, yFraction: 0.72)
        }
        .frame(width: size, height: size)
    }

    private func bar(widthFraction: CGFloat, yFraction: CGFloat) -> some View {
        let width = size * widthFraction
        let height = max(1, size * barHeightFraction)
        let left = size * leftInsetFraction
        return Capsule()
            .fill(color)
            .frame(width: width, height: height)
            .position(x: left + width / 2, y: size * yFraction)
    }
}

enum AppLogoTheme {
    /// Matches `Theme.accent` in the menubar-popover prototypes.
    static let accent = Color(red: 0x3b / 255, green: 0x6e / 255, blue: 0xf5 / 255)
    static let lcdGreen = Color(red: 0.30, green: 0.92, blue: 0.55)
}

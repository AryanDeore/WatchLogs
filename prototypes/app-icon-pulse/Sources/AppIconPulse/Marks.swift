import SwiftUI

// The shipped menu-bar mark, copied verbatim from `prototypes/app-logo-concepts`
// (Concept A, `LogPlayMark`). Three stepped bars that read as a log list and as
// a play triangle. This prototype pairs it with variant 7 ("unit suffixed":
// 47min / 1h05) from `prototypes/app-icon-time`, and pulses *only the mark*
// while a video is playing.
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

enum PulsePalette {
    static let accent = Color(red: 0x3b / 255, green: 0x6e / 255, blue: 0xf5 / 255)
}

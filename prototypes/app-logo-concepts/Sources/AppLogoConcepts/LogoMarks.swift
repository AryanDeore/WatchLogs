import SwiftUI

// Two app-icon concepts for WatchLogs itself, drawn the same way ServiceLogo.swift
// draws Netflix/Twitch/YouTube: simple vector shapes in a normalized coordinate
// box, not artwork. Both are sketches for issue discussion, not final assets.

/// Concept A — "logs + watch": three horizontal bars (a log/list of entries)
/// whose right edges step outward to a peak, so the same three strokes also
/// read as a play triangle. Dual reading: list of watch-log entries, and the
/// universal "watch this" glyph.
struct LogPlayMark: View {
    var size: CGFloat = 120
    var color: Color = AppLogoTheme.accent

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
        let height = size * barHeightFraction
        let left = size * leftInsetFraction
        return Capsule()
            .fill(color)
            .frame(width: width, height: height)
            .position(x: left + width / 2, y: size * yFraction)
    }
}

/// Concept B — a "Watch_Dogs"-inspired mark: two pillars flanking a woven
/// hourglass, ringed by a circle. This is a loose vector approximation of
/// the shape (Watch_Dogs is Ubisoft's trademark; nothing here is traced from
/// their asset) chosen for the pun — WatchLogs / Watch Dogs.
struct WatchDogsMark: View {
    var size: CGFloat = 120
    var color: Color = AppLogoTheme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: size * 0.045)
            WatchDogsGlyph()
                .stroke(style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round, lineJoin: .round))
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
    }
}

private struct WatchDogsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        // Normalized to a 100x100 box, then scaled to `rect`.
        let w = rect.width / 100, h = rect.height / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        // Left pillar.
        path.move(to: p(30, 18))
        path.addLine(to: p(30, 82))
        // Right pillar.
        path.move(to: p(70, 18))
        path.addLine(to: p(70, 82))
        // Hourglass/bowtie diagonals, pinched at the center.
        path.move(to: p(30, 18))
        path.addLine(to: p(70, 82))
        path.move(to: p(70, 18))
        path.addLine(to: p(30, 82))
        // Crossbar through the pinch point.
        path.move(to: p(30, 50))
        path.addLine(to: p(70, 50))
        return path
    }
}

enum AppLogoTheme {
    // Matches Theme.accent in the menubar-popover prototypes, so this mark
    // stays consistent with the rest of the app's palette.
    static let accent = Color(red: 0x3b / 255, green: 0x6e / 255, blue: 0xf5 / 255)
}

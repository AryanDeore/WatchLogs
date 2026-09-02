import SwiftUI

// Recognizable brand marks drawn as vectors, rather than shipping real
// trademarked artwork into the repo (and rather than v1/v2's generic SF
// Symbols, which made every service look the same). These are
// approximations for a throwaway prototype — a real build should use each
// service's official asset under its brand guidelines, or a licensed
// icon set.
//
// NOTE the tension this creates: the logos are brand-accurate, so YouTube
// and Netflix are BOTH red here, while the charts keep the legibility
// palette (Netflix = amber) so stacked bars stay readable. Identity marks
// next to a text label can afford to collide; comparison bars can't. Worth
// a decision before this ships.
struct ServiceLogo: View {
    let service: Service
    var size: CGFloat = 15

    var body: some View {
        switch service {
        case .youtube: YouTubeMark(size: size)
        case .netflix: NetflixMark(size: size)
        case .twitch: TwitchMark(size: size)
        case .other: OtherMark(size: size)
        }
    }
}

private struct YouTubeMark: View {
    let size: CGFloat

    var body: some View {
        // The play "badge": a red rounded rectangle with a white triangle.
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(red: 1.0, green: 0.0, blue: 0.0))
            .frame(width: size, height: size * 0.72)
            .overlay {
                Triangle()
                    .fill(.white)
                    .frame(width: size * 0.24, height: size * 0.28)
                    .offset(x: size * 0.02)
            }
            .frame(width: size, height: size)
    }
}

private struct NetflixMark: View {
    let size: CGFloat

    var body: some View {
        // The wordmark's "N" — Netflix red, heavy and tight.
        Text("N")
            .font(.system(size: size * 0.95, weight: .heavy, design: .default))
            .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
            .frame(width: size, height: size)
    }
}

private struct TwitchMark: View {
    let size: CGFloat

    var body: some View {
        // The chat-bubble glitch silhouette, simplified.
        TwitchGlyph()
            .fill(Color(red: 0.569, green: 0.275, blue: 1.0), style: FillStyle(eoFill: true))
            .frame(width: size * 0.82, height: size * 0.9)
            .frame(width: size, height: size)
    }
}

private struct OtherMark: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "globe")
            .font(.system(size: size * 0.85))
            .foregroundStyle(Service.other.color)
            .frame(width: size, height: size)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct TwitchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        // Normalized to a 100x112 box, then scaled to `rect`.
        let w = rect.width / 100, h = rect.height / 112
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        // Outer body: a bubble with the notched bottom-left tail.
        path.move(to: p(11, 0))
        path.addLine(to: p(100, 0))
        path.addLine(to: p(100, 64))
        path.addLine(to: p(78, 86))
        path.addLine(to: p(56, 86))
        path.addLine(to: p(34, 108))
        path.addLine(to: p(34, 86))
        path.addLine(to: p(0, 86))
        path.addLine(to: p(0, 22))
        path.closeSubpath()
        // The two "eye" slots, punched out via the even-odd fill rule.
        path.addRect(CGRect(origin: p(45, 25), size: CGSize(width: 11 * w, height: 34 * h)))
        path.addRect(CGRect(origin: p(72, 25), size: CGSize(width: 11 * w, height: 34 * h)))
        return path
    }
}

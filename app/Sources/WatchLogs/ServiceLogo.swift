import SwiftUI
import WatchLogsKit

// Recognizable brand marks drawn as vectors, rather than shipping real
// trademarked artwork into the repo (and rather than generic SF Symbols, which
// make every service look the same). These are approximations — a real build
// should use each service's official asset under its brand guidelines, or a
// licensed icon set.
//
// The tension worth calling out: logos are brand-accurate, so a red YouTube
// mark sits next to a red Netflix mark, while the charts keep a legibility
// palette (see `bucketColor`) so stacked bars stay readable. Identity marks
// next to a text label can afford to collide; comparison bars can't.
struct ServiceLogo: View {
    let service: ServiceDisplayBucket
    var size: CGFloat = 15

    var body: some View {
        switch service {
        case .youtube: YouTubeMark(size: size)
        case .netflix: NetflixMark(size: size)


        case .otherSites: OtherMark(size: size)
        }
    }
}

private struct YouTubeMark: View {
    let size: CGFloat

    var body: some View {
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
        Text("N")
            .font(.system(size: size * 0.95, weight: .heavy, design: .default))
            .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
            .frame(width: size, height: size)
    }
}

private struct OtherMark: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "globe")
            .font(.system(size: size * 0.85))
            .foregroundStyle(bucketColor(.otherSites))
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

/// Legibility palette used by every stacked bar and chart, deliberately not the
/// brand colours the logos use. YouTube and Netflix are both red in reality,
/// which reads as one segment when they sit side by side in a chart.
func bucketColor(_ bucket: ServiceDisplayBucket) -> Color {
    switch bucket {
    case .youtube: Color(red: 0.898, green: 0.204, blue: 0.169) // #e5342b
    case .netflix: Color(red: 0.878, green: 0.565, blue: 0.184) // #e0902f
    case .otherSites: Color(red: 0.604, green: 0.631, blue: 0.678) // #9aa1ad
    }
}

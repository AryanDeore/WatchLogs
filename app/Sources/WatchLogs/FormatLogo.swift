import SwiftUI

// The three YouTube content formats, drawn as marks instead of spelled out.
// The words "videos / shorts / live" needed a 40pt gutter, which pushed the
// breakdown bars out of line with the service bar above them; a mark needs
// the same 15pt slot the service logo already occupies, so every bar in the
// pane can start on one grid line.
//
// Same caveat as ServiceLogo: hand-drawn approximations for the prototype,
// not shipped trademarked artwork. A real build should use YouTube's own
// assets under its brand guidelines.
enum ContentFormat: String, CaseIterable {
    case video, short, live

    /// `TotalsSlice.contentFormat` uses "standard"/"short"/"live"; the older
    /// prototype label was "videos"/"shorts"/"live". Both land here.
    init?(label: String) {
        switch label {
        case "video", "videos", "standard": self = .video
        case "short", "shorts": self = .short
        case "live": self = .live
        default: return nil
        }
    }

    var name: String {
        switch self {
        case .video: "Videos"
        case .short: "Shorts"
        case .live: "Live"
        }
    }
}

struct FormatLogo: View {
    let format: ContentFormat
    var size: CGFloat = 15

    var body: some View {
        switch format {
        case .video: VideoMark(size: size)
        case .short: ShortsMark(size: size)
        case .live: LiveMark(size: size)
        }
    }
}

private let youTubeRed = Color(red: 1.0, green: 0.0, blue: 0.0)
private let liveRed = Color(red: 0.957, green: 0.263, blue: 0.212) // #f44336

private struct VideoMark: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(youTubeRed)
            .frame(width: size * 0.90, height: size * 0.90)
            .overlay {
                PlayTriangle()
                    .fill(.white)
                    .frame(width: size * 0.26, height: size * 0.30)
                    .offset(x: size * 0.03)
            }
            .frame(width: size, height: size)
    }
}

private struct ShortsMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            ShortsGlyph().fill(youTubeRed)
            ShortsPlayGlyph().fill(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Traced from YouTube's Shorts mark on its native 48x48 grid, then scaled to
/// `rect`. Kept as literal coordinates rather than tidied into parameters:
/// they are one artwork, and rounding any of them made the capsule
/// approximation look off.
private struct ShortsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 48, h = rect.height / 48
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: p(29.103, 2.631))
        path.addCurve(to: p(40.761, 6.208), control1: p(33.320, 0.433), control2: p(38.541, 2.034))
        path.addCurve(to: p(37.144, 17.742), control1: p(42.981, 10.381), control2: p(41.361, 15.545))
        path.addLine(to: p(33.676, 19.565))
        path.addCurve(to: p(41.004, 24.120), control1: p(36.663, 19.674), control2: p(39.512, 21.315))
        path.addCurve(to: p(37.387, 35.654), control1: p(43.224, 28.293), control2: p(41.608, 33.457))
        path.addLine(to: p(18.897, 45.370))
        path.addCurve(to: p(7.239, 41.793), control1: p(14.680, 47.568), control2: p(9.459, 45.967))
        path.addCurve(to: p(10.856, 30.259), control1: p(5.019, 37.619), control2: p(6.639, 32.456))
        path.addLine(to: p(14.324, 28.436))
        path.addCurve(to: p(6.996, 23.881), control1: p(11.337, 28.327), control2: p(8.488, 26.686))
        path.addCurve(to: p(10.613, 12.347), control1: p(4.776, 19.708), control2: p(6.396, 14.544))
        path.addCurve(to: p(29.103, 2.631), control1: p(10.612, 12.346), control2: p(29.103, 2.631))
        path.closeSubpath()
        return path
    }
}

private struct ShortsPlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 48, h = rect.height / 48
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: p(19.122, 17.120))
        path.addLine(to: p(30.314, 24.030))
        path.addLine(to: p(19.122, 30.907))
        path.closeSubpath()
        return path
    }
}

private struct LiveMark: View {
    let size: CGFloat

    var body: some View {
        LiveGlyph().fill(liveRed)
            .frame(width: size, height: size)
    }
}

private struct LiveGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 48, h = rect.height / 48
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()

        path.addEllipse(in: CGRect(origin: p(18, 18), size: CGSize(width: 12 * w, height: 12 * h)))

        path.move(to: p(17.090, 16.789))
        path.addLine(to: p(14.321, 13.900))
        path.addCurve(to: p(10.000, 24.000), control1: p(11.663, 16.448), control2: p(10.000, 20.027))
        path.addCurve(to: p(14.321, 34.100), control1: p(10.000, 27.973), control2: p(11.663, 31.552))
        path.addLine(to: p(17.090, 31.211))
        path.addCurve(to: p(14.000, 24.000), control1: p(15.190, 29.389), control2: p(14.000, 26.833))
        path.addCurve(to: p(17.090, 16.789), control1: p(14.000, 21.167), control2: p(15.190, 18.610))
        path.closeSubpath()

        path.move(to: p(33.679, 13.900))
        path.addLine(to: p(30.910, 16.789))
        path.addCurve(to: p(34.000, 24.000), control1: p(32.810, 18.611), control2: p(34.000, 21.167))
        path.addCurve(to: p(30.910, 31.211), control1: p(34.000, 26.833), control2: p(32.810, 29.389))
        path.addLine(to: p(33.679, 34.100))
        path.addCurve(to: p(38.000, 24.000), control1: p(36.337, 31.552), control2: p(38.000, 27.973))
        path.addCurve(to: p(33.679, 13.900), control1: p(38.000, 20.027), control2: p(36.337, 16.448))
        path.closeSubpath()

        path.move(to: p(11.561, 11.021))
        path.addLine(to: p(8.782, 8.121))
        path.addCurve(to: p(2.000, 24.000), control1: p(4.605, 12.125), control2: p(2.000, 17.757))
        path.addCurve(to: p(8.782, 39.879), control1: p(2.000, 30.243), control2: p(4.605, 35.875))
        path.addLine(to: p(11.561, 36.979))
        path.addCurve(to: p(6.000, 24.000), control1: p(8.142, 33.701), control2: p(6.000, 29.100))
        path.addCurve(to: p(11.561, 11.021), control1: p(6.000, 18.900), control2: p(8.142, 14.299))
        path.closeSubpath()

        path.move(to: p(39.218, 8.121))
        path.addLine(to: p(36.439, 11.021))
        path.addCurve(to: p(42.000, 24.000), control1: p(39.858, 14.299), control2: p(42.000, 18.900))
        path.addCurve(to: p(36.439, 36.979), control1: p(42.000, 29.100), control2: p(39.858, 33.701))
        path.addLine(to: p(39.218, 39.879))
        path.addCurve(to: p(46.000, 24.000), control1: p(43.395, 35.875), control2: p(46.000, 30.243))
        path.addCurve(to: p(39.218, 8.121), control1: p(46.000, 17.757), control2: p(43.395, 12.125))
        path.closeSubpath()

        return path
    }
}

private struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

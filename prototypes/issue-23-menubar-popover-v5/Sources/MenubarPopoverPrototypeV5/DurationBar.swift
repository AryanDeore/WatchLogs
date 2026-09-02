import SwiftUI

// Bar height is a property of the pane, not of the selected range: a bar
// that changed thickness when you switched Today → This Week read as the
// layout drifting rather than as a deliberate weight.
enum BarMetrics {
    // History: one bar per video, nested under a day header and indented.
    // It annotates a row that already says everything important in text, so
    // it stays the lightest mark in the panel.
    static let history: CGFloat = 2

    // Services and Trends: here the bar *is* the content — it's the only
    // thing carrying the comparison between services or between days — so
    // it earns a point over History's.
    static let pane: CGFloat = 3
}

// Replaces the stock ProgressView, which on macOS renders thick and fully
// saturated — every row read as equally "important" whether it was a
// 3-second Short or a 2-hour movie. Heights settled after paging through
// prototype v6's sweep (stock, 5/4/3/2/1pt): thin enough to read as a
// detail rather than a headline, without losing the fill/track contrast
// that answers "did I finish this?" at a glance.
struct DurationBar: View {
    let fraction: Double
    let height: CGFloat
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(tint)
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: height)
    }
}

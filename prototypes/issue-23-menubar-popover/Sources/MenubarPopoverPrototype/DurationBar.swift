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
    // Services turns this off: with several of these stacked (a service row
    // plus its format breakdown), a full-width track behind every one of
    // them reads as "these are all the same size," which is exactly what
    // the fraction-of-grand-total change below is trying to correct.
    var showsTrack: Bool = true
    // How much narrower this bar's own box is than the pane's shared plot.
    // A nested row is indented, so its box is short by exactly the indent —
    // and a fraction of that shorter box would draw a slice visibly smaller
    // than its true share of the bar it is nested under. Adding the indent
    // back here measures every bar against one ruler no matter how deeply
    // its row sits.
    var narrowerThanPlotBy: CGFloat = 0
    // A run of solid colour before the measured length starts, drawn back out
    // of the box's leading edge. It carries no data: it exists so a bar can
    // *look* like it begins under its own row's first letter while still
    // being measured from the line every other bar starts on. Services uses
    // it on the service rows; anything comparing two bars that don't share
    // the same lead-in is comparing their right edges, not their lengths.
    var leadIn: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let plot = geo.size.width + narrowerThanPlotBy
            ZStack(alignment: .leading) {
                if showsTrack {
                    Capsule().fill(Color.primary.opacity(0.10))
                }
                Capsule().fill(tint)
                    .frame(width: leadIn + plot * max(0, min(1, fraction)))
                    .offset(x: -leadIn)
            }
        }
        .frame(height: height)
    }
}

import SwiftUI

// The thing under test: how tall should the per-video "how much of this did
// you watch" bar be? HistoryPane in v1/v2/v4/v5 all use a stock
// `ProgressView(value:)` for this — which on macOS renders as a fairly tall,
// fully-saturated track that reads as "important" even for a 3-minute
// Short. That's variant A here. B through F are the same capsule at
// decreasing heights, everything else (track opacity, tint, corner
// radius) held constant, so height is the only variable being judged.
enum BarVariant: String, CaseIterable, Identifiable {
    case stock, h5, h4, h3, h2, h1

    var id: String { rawValue }

    var name: String {
        switch self {
        case .stock: "A · Stock ProgressView (today)"
        case .h5: "B · 5pt capsule"
        case .h4: "C · 4pt capsule"
        case .h3: "D · 3pt capsule"
        case .h2: "E · 2pt capsule"
        case .h1: "F · 1pt hairline"
        }
    }

    // nil = let the system pick (that's the point of the "stock" variant).
    var height: CGFloat? {
        switch self {
        case .stock: nil
        case .h5: 5
        case .h4: 4
        case .h3: 3
        case .h2: 2
        case .h1: 1
        }
    }

    // A thinner bar shrinks each row, so a naive swap makes six rows sit
    // more tightly together as height drops — a side effect of the sweep,
    // not the thing being judged. These two give back roughly what the bar
    // gave up (as gap above the bar, and as gap between rows) so the six
    // rows occupy about the same total height at every variant, and only
    // the bar's boldness is actually changing.
    private var reclaimedHeight: CGFloat { 6 - (height ?? 6) }

    var barTopGap: CGFloat { 4 + reclaimedHeight * 0.6 }
    var rowSpacing: CGFloat { 10 + reclaimedHeight * 1.5 }

    var note: String {
        switch self {
        case .stock:
            "What ships today. macOS's own linear ProgressView — no explicit height, but its default track reads thick and fully saturated next to a caption-sized title. Every row looks equally \"important,\" whether it's a 3-second Short or a 2-hour movie."
        case .h5:
            "A hand-rolled capsule at 5pt — close to stock's rendered height, kept as the top of the sweep so there's a like-for-like reference point before going thinner."
        case .h4:
            "4pt. Still readable as a progress bar at a glance, noticeably quieter than stock. This is roughly what the aggregate Trends bars use elsewhere, so picking this here means one thickness language across the whole popover."
        case .h3:
            "3pt. The bar starts reading as a detail rather than a headline — you register \"there's a fill amount\" without it competing with the title text above it."
        case .h2:
            "2pt. Close to a rule/divider's weight. Coverage is still legible (fill vs. track color contrast carries it), but at a glance a fully-watched row and an empty row look almost the same until you look for it."
        case .h1:
            "1pt hairline. Barely there — arguably too subtle for a signal the user might actually want to scan (\"did I finish this?\"). Included as the floor of the sweep, not a real candidate."
        }
    }
}

// The hand-rolled bar all non-stock variants share. Rounded caps at every
// height keep the "capsule" language consistent instead of square-ended
// bars starting to look like plain rules once they get thin.
struct DurationBar: View {
    let coverage: Double
    let height: CGFloat
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(tint)
                    .frame(width: geo.size.width * coverage)
            }
        }
        .frame(height: height)
    }
}

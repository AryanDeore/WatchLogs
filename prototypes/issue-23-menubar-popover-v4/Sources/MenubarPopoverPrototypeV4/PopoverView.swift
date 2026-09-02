import SwiftUI

struct PopoverView: View {
    @State private var store = PopoverStore()
    @State private var chromeHeight: CGFloat = 0
    @State private var paneContentHeight: CGFloat = 0

    // v2's popover was 380pt wide with the rail added on top (435 total).
    // That read as too wide, so the window is now 15% narrower than that
    // (435 * 0.85 ≈ 370) — taken out of the pane column rather than the
    // rail, since the rail's 44pt items are already close to the minimum
    // that still fits an icon + an 8pt label.
    private static let windowWidth: CGFloat = 370
    private static let paneWidth: CGFloat = windowWidth - PaneRail.width - 1 // -1 = divider

    // Floor on the sizing math below: below it, a near-empty pane (e.g.
    // Today with one view) would shrink the window to an awkward sliver.
    private static let minHeight: CGFloat = 420
    private static let settingsHeight: CGFloat = 560

    // The ceiling was originally a guessed constant (720pt) — too low: an
    // expanded month grid plus a 14-day Trends chart both together need more
    // than that, so the guess clamped the window and brought back the exact
    // scrolling this was meant to fix. The only real ceiling is the screen
    // itself, so this reads it directly rather than guessing again.
    private var maxHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return screenHeight - 40 // margin so the popover doesn't touch the screen edges
    }

    // Sized to fit what's actually on screen instead of a fixed 560: the
    // calendar alone swings from a ~50pt week row to a ~190pt month grid,
    // and pane content varies just as much (a 3-day History vs. a 14-day
    // Trends chart), so no single fixed height leaves the chart visible
    // without scrolling in every state.
    private var windowHeight: CGFloat {
        guard !store.settingsOpen else { return Self.settingsHeight }
        return min(max(chromeHeight + paneContentHeight, Self.minHeight), maxHeight)
    }

    var body: some View {
        // Settings replaces the panes rather than sitting on top of them, so
        // it can inherit the popover's own material instead of needing an
        // opaque background of its own to hide what's behind it.
        ZStack {
            if store.settingsOpen {
                SettingsView(store: store)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        TitleRow(store: store)
                        Divider()
                        RangePicker(store: store)
                        CalendarBox(store: store)
                        Divider()
                        SummaryStrip(store: store)
                        Divider()
                    }
                    .measureHeight { chromeHeight = $0 }

                    // The rail starts here, not at the top of the window: it
                    // switches panes, and everything above it (range, calendar,
                    // summary) applies to all three panes equally. A full-height
                    // sidebar would imply it governed those too.
                    HStack(spacing: 0) {
                        PaneRail(store: store)
                        Divider()
                        ThinScrollView(onContentHeightChange: { paneContentHeight = $0 }) {
                            paneBody
                        }
                        .frame(width: Self.paneWidth)
                    }
                }
                .transition(.move(edge: .leading))
            }
        }
        .frame(width: Self.windowWidth, height: windowHeight)
        // Vibrancy material instead of v1's flat white — matches how native
        // menu-bar utilities (e.g. CodexBar) let the desktop bleed through.
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.18), value: store.settingsOpen)
        .animation(.easeOut(duration: 0.18), value: windowHeight)
    }

    @ViewBuilder
    private var paneBody: some View {
        switch store.pane {
        case .history: HistoryPane(store: store)
        case .byService: ByServicePane(store: store)
        case .trends: TrendsPane(store: store)
        }
    }
}

import SwiftUI

struct PopoverView: View {
    @State private var store = PopoverStore()

    // v2's popover was 380pt wide. The rail is added to that rather than
    // carved out of it, so the panes are still laid out at exactly 380 and
    // stay directly comparable to v2's.
    private static let paneWidth: CGFloat = 380
    private static let windowWidth = paneWidth + PaneRail.width + 1 // +1 = divider

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
                    TitleRow(store: store)
                    Divider()
                    RangePicker(store: store)
                    CalendarBox(store: store)
                    Divider()
                    SummaryStrip(store: store)
                    Divider()
                    // The rail starts here, not at the top of the window: it
                    // switches panes, and everything above it (range, calendar,
                    // summary) applies to all three panes equally. A full-height
                    // sidebar would imply it governed those too.
                    HStack(spacing: 0) {
                        PaneRail(store: store)
                        Divider()
                        ThinScrollView {
                            paneBody
                        }
                        .frame(width: Self.paneWidth)
                    }
                }
                .transition(.move(edge: .leading))
            }
        }
        .frame(width: Self.windowWidth, height: 560)
        // Vibrancy material instead of v1's flat white — matches how native
        // menu-bar utilities (e.g. CodexBar) let the desktop bleed through.
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.18), value: store.settingsOpen)
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

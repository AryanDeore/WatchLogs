import SwiftUI

struct PopoverView: View {
    @State private var store = PopoverStore()

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
                    TabBar(store: store)
                    Divider()
                    ThinScrollView {
                        paneBody
                    }
                }
                .transition(.move(edge: .leading))
            }
        }
        .frame(width: 380, height: 560)
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

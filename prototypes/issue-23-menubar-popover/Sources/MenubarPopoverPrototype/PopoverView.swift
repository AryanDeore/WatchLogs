import SwiftUI

struct PopoverView: View {
    @State private var store = PopoverStore()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TitleRow(store: store)
                PresetChips(store: store)
                CalendarBox(store: store)
                SummaryStrip(store: store)
                TabsBar(store: store)
                ScrollView {
                    paneBody
                }
            }

            if store.settingsOpen {
                SettingsView(store: store)
                    .background(.background)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .frame(width: 380, height: 560)
        .background(.background)
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

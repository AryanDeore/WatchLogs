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
            .background(Theme.card)

            if store.settingsOpen {
                SettingsView(store: store)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .frame(width: 380, height: 560)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .animation(.easeOut(duration: 0.18), value: store.settingsOpen)
        .preferredColorScheme(.light)
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

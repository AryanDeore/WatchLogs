import Observation
import SwiftUI
import WatchLogsKit

struct PopoverView: View {
    let model: MenubarPopoverReadModel
    let transport: LoopbackTransport
    @State private var chromeHeight: CGFloat = 0
    @State private var paneContentHeight: CGFloat = 0
    @State private var tick = Date()

    private static let width: CGFloat = 380
    /// Floor: below this a near-empty pane (Today with one view) would shrink
    /// the window to an awkward sliver.
    private static let minHeight: CGFloat = 420
    private static let settingsHeight: CGFloat = 560

    /// The ceiling reads the current screen instead of a guessed constant, so
    /// an expanded month grid plus a 14-day Trends chart both fit without
    /// bringing back the exact scrolling this sizing was meant to remove.
    private var maxHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return screenHeight - 40
    }

    private var windowHeight: CGFloat {
        guard !model.settingsOpen else { return Self.settingsHeight }
        return min(max(chromeHeight + paneContentHeight, Self.minHeight), maxHeight)
    }

    var body: some View {
        let data = model.resolved
        // Settings replaces the panes rather than sitting on top of them, so
        // it can share the popover's own material and the ZStack never renders
        // both layers at once.
        ZStack {
            if model.settingsOpen {
                SettingsView(model: model, transport: transport)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        TitleRow(model: model, data: data)
                        Divider()
                        RangePicker(model: model)
                        CalendarBox(model: model, data: data)
                        Divider()
                        SummaryStrip(model: model, data: data)
                        Divider()
                        TabBar(model: model)
                        Divider()
                    }
                    .measureHeight { chromeHeight = $0 }

                    ThinScrollView(onContentHeightChange: { paneContentHeight = $0 }) {
                        paneBody(data)
                    }
                }
                .transition(.move(edge: .leading))
            }
        }
        .frame(width: Self.width, height: windowHeight)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.18), value: model.settingsOpen)
        .animation(.easeOut(duration: 0.18), value: windowHeight)
        .onAppear { _ = tick }
        // Refresh open-Day data periodically so the "still open" total keeps up
        // with real time without waiting for a Flush to arrive.
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { tick = $0 }
    }

    @ViewBuilder
    private func paneBody(_ data: MenubarPopoverData) -> some View {
        switch model.pane {
        case .history: HistoryPane(data: data)
        case .byService: ByServicePane(model: model, data: data)
        case .trends: TrendsPane(data: data)
        }
    }
}

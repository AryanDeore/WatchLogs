import SwiftUI

// PROTOTYPE — throwaway. v6 answers a narrower question spun out of issue
// #23's History pane: the per-video "how much did you watch" bar (currently
// a stock ProgressView) reads too bold. This is a gallery in the same shape
// as v3's pane-switcher gallery — same popover shell, same fictional
// history rows, with just the bar swapped between height options via the
// bottom bar.
//
// Menu-bar icon is the numeral "6" so v1–v6 can run side by side.
@main
struct MenubarPopoverPrototypeV6App: App {
    var body: some Scene {
        MenuBarExtra("WatchLogs (v6)", systemImage: "6.circle.fill") {
            BarGalleryView()
        }
        .menuBarExtraStyle(.window)
    }
}

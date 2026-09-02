import SwiftUI

// PROTOTYPE — throwaway. v5 of issue #23's menu-bar popover exploration.
// Identical to v2 (prototypes/issue-23-menubar-popover-v2/) in every respect
// except the pane switcher: v2's icon+label bar is replaced by variant A from
// the v3 switcher gallery — a stock `Picker(.segmented)`. Same 380pt width,
// so it can be compared to v2 head-to-head.
//
// The menu-bar icon is a numeral so multiple prototype versions can run
// side by side and stay distinguishable: this one is "5".
@main
struct MenubarPopoverPrototypeV5App: App {
    var body: some Scene {
        MenuBarExtra("WatchLogs (v5)", systemImage: "5.circle.fill") {
            PopoverView()
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI

// PROTOTYPE — throwaway. v4 of issue #23's menu-bar popover exploration.
// Identical to v2 (prototypes/issue-23-menubar-popover-v2/) in every respect
// except the pane switcher: v2's icon+label bar across the top is replaced by
// variant F from the v3 switcher gallery — a vertical sidebar rail down the
// left edge of the pane area. The window is widened by exactly the rail's
// width so the panes keep v2's 380pt and the two can be compared directly.
//
// The menu-bar icon is a numeral so multiple prototype versions can run
// side by side and stay distinguishable: this one is "4".
@main
struct MenubarPopoverPrototypeV4App: App {
    var body: some Scene {
        MenuBarExtra("WatchLogs (v4)", systemImage: "4.circle.fill") {
            PopoverView()
        }
        .menuBarExtraStyle(.window)
    }
}

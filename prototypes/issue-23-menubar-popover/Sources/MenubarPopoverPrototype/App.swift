import SwiftUI

// PROTOTYPE — throwaway. Issue #23's menu-bar popover, the design that was
// settled on: v2's native chrome with variant A of the v3 switcher gallery
// (a stock `Picker(.segmented)`) as the pane switcher. The versions it was
// picked over — v1 through v4 and v6 — were deleted once the decision was
// made; they are in the history behind commit 85d5ba2 if the comparison is
// ever needed again.
@main
struct MenubarPopoverPrototypeApp: App {
    var body: some Scene {
        // Was `5.circle.fill`: a numeral, so several prototype versions could
        // sit in the menu bar at once and stay apart. There is only one now,
        // so it carries the app's own mark instead.
        MenuBarExtra {
            PopoverView()
        } label: {
            Image(nsImage: .logPlayMarkTemplate())
        }
        .menuBarExtraStyle(.window)
    }
}

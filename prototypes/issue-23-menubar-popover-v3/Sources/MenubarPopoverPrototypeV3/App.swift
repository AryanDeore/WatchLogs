import SwiftUI

// PROTOTYPE — throwaway. v3 answers ONE question pulled out of issue #23:
// what should the History / By Service / Trends switcher look like?
//
// v1 used flat pill tabs, v2 an icon+label row. Neither felt settled, so
// this prototype is a gallery: the same popover shell and the same stub
// pane content, with the switcher swapped between eight candidate designs
// via a bottom bar (the same trick prototypes/menubar-layout/index.html
// used for its A/B/C rounds).
//
// Menu-bar icon is the numeral "3" so v1 / v2 / v3 can run side by side.
@main
struct MenubarPopoverPrototypeV3App: App {
    var body: some Scene {
        MenuBarExtra("WatchLogs (v3)", systemImage: "3.circle.fill") {
            SwitcherGalleryView()
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI

// PROTOTYPE — throwaway. v2 of issue #23's menu-bar popover exploration.
// v1 (prototypes/issue-23-menubar-popover/) ported the converged HTML
// mockup (prototypes/menubar-layout/, issue #7) close to 1:1. That looked
// "100% like a web page" — this version keeps the same information
// architecture (title row, range selector, calendar, summary strip,
// History/By Service/Trends, Settings) but rebuilds the chrome out of
// native macOS idioms instead: vibrancy material, Picker(.segmented),
// DisclosureGroup, ProgressView, Swift Charts, and a native Form for
// Settings — closer to how a real menu-bar utility (e.g. CodexBar) looks.
//
// The menu-bar icon is a numeral so multiple prototype versions can run
// side by side and stay distinguishable: this one is "2".
@main
struct MenubarPopoverPrototypeV2App: App {
    var body: some Scene {
        MenuBarExtra("WatchLogs (v2)", systemImage: "2.circle.fill") {
            PopoverView()
        }
        .menuBarExtraStyle(.window)
    }
}

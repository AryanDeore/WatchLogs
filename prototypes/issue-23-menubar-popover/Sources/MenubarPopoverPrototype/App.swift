import SwiftUI

// PROTOTYPE — throwaway. Answers issue #23 on top of the converged layout
// pinned by prototypes/menubar-layout/ (issue #7): does the round-5 HTML
// design hold up as a real SwiftUI menu-bar popover? Mock data only, no
// wiring to WatchLogsKit's read model.
@main
struct MenubarPopoverPrototypeApp: App {
    var body: some Scene {
        MenuBarExtra("WatchLogs (v1)", systemImage: "1.circle.fill") {
            PopoverView()
        }
        .menuBarExtraStyle(.window)
    }
}

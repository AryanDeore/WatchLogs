import SwiftUI

// Variant A from the v3 switcher gallery, promoted into v2's full chrome.
// The stock macOS segmented control — no custom drawing at all, so it picks
// up system selection behaviour, focus ring, and Dark Mode for free.
//
// Note what this puts on screen: the range presets directly above are also
// a segmented Picker, so the panel now opens with two of them stacked. That
// is the thing to judge here — whether "familiar control" wins over "the
// same control twice, meaning two different kinds of thing."
struct TabBar: View {
    @Bindable var store: PopoverStore

    var body: some View {
        Picker("", selection: $store.pane) {
            ForEach(Pane.allCases) { pane in
                Text(pane.label).tag(pane)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

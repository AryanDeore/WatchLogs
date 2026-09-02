import SwiftUI

// Variant A from the v3 switcher gallery, promoted into v2's full chrome —
// the segmented control, now carrying v2's icons inline with each label.
//
// Getting there took three tries, worth recording so it isn't re-litigated:
// a SwiftUI `Label` inside a segmented Picker renders title-only, a `Text`
// with an inline `Image` drops the attachment, and a hand-drawn HStack of
// buttons is an approximation of the system control in every dimension.
// The real NSSegmentedControl does icon + label natively, so TabBar wraps
// that instead (see NativeSegmentedControl.swift).
//
// Note what this puts on screen: the range presets directly above are also
// a segmented control, so the panel opens with two of them stacked. That is
// the thing to judge here — whether "familiar control" wins over "the same
// control twice, meaning two different kinds of thing." The icons at least
// give this one a different silhouette than the plain text row above it.
struct TabBar: View {
    @Bindable var store: PopoverStore

    var body: some View {
        NativeSegmentedControl(selection: $store.pane)
            .frame(height: 24) // the control's own intrinsic height
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)
    }
}

import SwiftUI
import WatchLogsKit

/// Wraps `NSSegmentedControl` because SwiftUI's segmented `Picker` won't
/// render an icon inline with its label (a `Label` gets flattened, a `Text` +
/// inline `Image` drops the attachment). The native control does icon+label
/// natively, so this matches the range Picker directly above by construction.
struct TabBar: View {
    let model: MenubarPopoverReadModel

    var body: some View {
        NativeSegmentedControl(
            selection: Binding(get: { model.pane }, set: { model.pane = $0 })
        )
        .frame(height: 24)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

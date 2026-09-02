import AppKit
import SwiftUI

// SwiftUI's `Picker(.segmented)` will not draw an icon in a segment: a
// `Label` gets flattened to its title, and a `Text` with an inline `Image`
// drops the attachment. AppKit's NSSegmentedControl has no such problem —
// `setImage` and `setLabel` on the same segment renders both, side by side.
//
// So rather than hand-approximating the system control in SwiftUI (track
// fill, corner radius, segment height, selection shadow, vibrancy, Dark
// Mode — six things to get subtly wrong), this wraps the real one. It IS
// the native control, so it matches the range Picker directly above it by
// construction rather than by eye.
struct NativeSegmentedControl: NSViewRepresentable {
    @Binding var selection: Pane

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = Pane.allCases.count
        control.segmentStyle = .automatic
        control.trackingMode = .selectOne
        // Equal-width segments, matching how the SwiftUI segmented Picker
        // above divides its row.
        control.segmentDistribution = .fillEqually

        for (index, pane) in Pane.allCases.enumerated() {
            control.setLabel(pane.label, forSegment: index)
            control.setImage(
                NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.label),
                forSegment: index
            )
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }

        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))
        // Let SwiftUI's frame win over the control's own fitting width, so
        // it stretches the full popover width instead of hugging its text.
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        let index = Pane.allCases.firstIndex(of: selection) ?? 0
        if control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Pane>

        init(selection: Binding<Pane>) {
            self.selection = selection
        }

        @MainActor @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard Pane.allCases.indices.contains(index) else { return }
            selection.wrappedValue = Pane.allCases[index]
        }
    }
}

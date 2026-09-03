import AppKit
import SwiftUI
import WatchLogsKit

/// SwiftUI's `Picker(.segmented)` won't draw an icon in a segment: a `Label`
/// gets flattened to its title, and a `Text` with an inline `Image` drops the
/// attachment. AppKit's `NSSegmentedControl` has no such problem, so this
/// wraps the real one. Using the native control means the range Picker
/// directly above matches by construction, not by eye.
struct NativeSegmentedControl: NSViewRepresentable {
    @Binding var selection: MenubarPane

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = MenubarPane.allCases.count
        control.segmentStyle = .automatic
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually

        for (index, pane) in MenubarPane.allCases.enumerated() {
            control.setLabel(pane.title, forSegment: index)
            control.setImage(
                NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title),
                forSegment: index
            )
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }

        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        let index = MenubarPane.allCases.firstIndex(of: selection) ?? 0
        if control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        var selection: Binding<MenubarPane>

        init(selection: Binding<MenubarPane>) {
            self.selection = selection
        }

        @MainActor @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard MenubarPane.allCases.indices.contains(index) else { return }
            selection.wrappedValue = MenubarPane.allCases[index]
        }
    }
}

extension MenubarPane {
    var symbolName: String {
        switch self {
        case .history: "clock"
        case .byService: "chart.pie"
        case .trends: "chart.bar.xaxis"
        }
    }
}

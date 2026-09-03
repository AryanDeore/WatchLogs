import SwiftUI
import WatchLogsKit

struct RangePicker: View {
    let model: MenubarPopoverReadModel

    var body: some View {
        let selection = Binding<RangePreset>(
            get: { RangePreset.matching(model.range) },
            set: { pick($0) }
        )
        Picker("", selection: selection) {
            ForEach(RangePreset.allCases) { preset in
                Text(preset.label).tag(preset)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func pick(_ preset: RangePreset) {
        switch preset {
        case .today:
            model.selectRange(.today)
            model.calendarExpanded = false
            model.customStart = nil
            model.customEnd = nil
        case .thisWeek:
            model.selectRange(.thisWeek)
            model.calendarExpanded = false
            model.customStart = nil
            model.customEnd = nil
        case .thisMonth:
            model.selectRange(.thisMonth)
            model.calendarExpanded = false
            model.customStart = nil
            model.customEnd = nil
        case .custom:
            // Only Custom opens the full month grid — the resolved-range label
            // carries the orientation for the three fixed presets. Custom
            // needs the grid to actually pick arbitrary days.
            let day = model.customStart ?? Date()
            model.selectRange(.custom(from: day, through: model.customEnd ?? day))
            model.calendarExpanded = true
        }
    }
}

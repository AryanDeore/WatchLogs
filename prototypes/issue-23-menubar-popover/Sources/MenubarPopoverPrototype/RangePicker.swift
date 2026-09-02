import SwiftUI

struct RangePicker: View {
    @Bindable var store: PopoverStore

    var body: some View {
        Picker("", selection: Binding(
            get: { store.range },
            set: { store.pick($0) }
        )) {
            ForEach(RangePreset.allCases) { preset in
                Text(preset.label).tag(preset)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

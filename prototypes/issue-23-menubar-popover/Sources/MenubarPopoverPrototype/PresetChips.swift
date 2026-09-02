import SwiftUI

struct PresetChips: View {
    @Bindable var store: PopoverStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RangePreset.allCases) { preset in
                let isOn = store.range == preset
                Button(preset.label) { store.pick(preset) }
                    .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(isOn ? Theme.accent : Theme.card)
                    .foregroundStyle(isOn ? .white : Theme.inkDim)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .buttonStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isOn ? Theme.accent : Theme.line2, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
    }
}

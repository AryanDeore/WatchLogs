import SwiftUI

struct PresetChips: View {
    @Bindable var store: PopoverStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RangePreset.allCases) { preset in
                let isOn = store.range == preset
                Button(preset.label) { store.pick(preset) }
                    .font(.system(size: 11.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(isOn ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .foregroundStyle(isOn ? .white : .secondary)
                    .fontWeight(isOn ? .semibold : .regular)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .buttonStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isOn ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
    }
}

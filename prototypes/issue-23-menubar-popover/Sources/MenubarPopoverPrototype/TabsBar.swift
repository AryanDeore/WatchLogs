import SwiftUI

struct TabsBar: View {
    @Bindable var store: PopoverStore

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Pane.allCases) { pane in
                let isOn = store.pane == pane
                Button(pane.label) { store.pane = pane }
                    .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(isOn ? Color(nsColor: .controlBackgroundColor) : .clear)
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .overlay(Divider(), alignment: .bottom)
    }
}

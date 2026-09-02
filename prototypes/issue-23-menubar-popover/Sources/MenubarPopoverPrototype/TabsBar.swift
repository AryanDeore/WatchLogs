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
                    .background(isOn ? Theme.card : .clear)
                    .foregroundStyle(isOn ? Theme.ink : Theme.inkDim)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: isOn ? .black.opacity(0.12) : .clear, radius: 2, x: 0, y: 1)
                    .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.panel2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }
}

import SwiftUI

// Icon + label tab row, closer to how native menu-bar utilities (e.g.
// CodexBar's provider switcher) pick between a handful of top-level panes,
// instead of v1's flat pill tabs.
struct TabBar: View {
    @Bindable var store: PopoverStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Pane.allCases) { pane in
                let isOn = store.pane == pane
                Button {
                    store.pane = pane
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 15))
                            .frame(width: 30, height: 26)
                            .background(isOn ? Color.accentColor : .clear)
                            .foregroundStyle(isOn ? Color.white : Color.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text(pane.label)
                            .font(.caption2)
                            .foregroundStyle(isOn ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

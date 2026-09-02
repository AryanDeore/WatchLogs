import SwiftUI

// Variant F from the v3 switcher gallery, promoted into v2's full chrome.
// The switcher goes down the left edge instead of across the top, which
// takes it off the vertical budget entirely — but width in a menu-bar
// popover isn't free either, so the window grows by exactly the rail's
// width and the panes keep the same 380pt they had in v2.
struct PaneRail: View {
    @Bindable var store: PopoverStore

    // Rail geometry, hoisted so PopoverView can add it to the window width
    // rather than everyone guessing at the same numbers.
    static let itemWidth: CGFloat = 44
    static let horizontalPadding: CGFloat = 5
    static let width = itemWidth + horizontalPadding * 2

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Pane.allCases) { candidate in
                let isOn = store.pane == candidate
                Button {
                    store.pane = candidate
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: candidate.symbol)
                            .font(.system(size: 14))
                        Text(candidate.shortLabel)
                            .font(.system(size: 8))
                    }
                    .frame(width: Self.itemWidth, height: 40)
                    .background(isOn ? Color.accentColor : .clear)
                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(candidate.label)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Self.horizontalPadding)
        .background(Color.primary.opacity(0.04))
    }
}

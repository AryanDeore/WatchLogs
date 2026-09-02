import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case history, byService, trends

    var id: String { rawValue }

    var label: String {
        switch self {
        case .history: "History"
        case .byService: "By Service"
        case .trends: "Trends"
        }
    }

    // A shorter label for the variants where horizontal room is tight.
    var shortLabel: String {
        switch self {
        case .history: "History"
        case .byService: "Services"
        case .trends: "Trends"
        }
    }

    var symbol: String {
        switch self {
        case .history: "clock"
        case .byService: "chart.pie"
        case .trends: "chart.bar.xaxis"
        }
    }
}

enum SwitcherVariant: String, CaseIterable, Identifiable {
    case segmented, iconLabel, underline, pill, iconOnly, rail, menu, tile

    var id: String { rawValue }

    var name: String {
        switch self {
        case .segmented: "A · Segmented control"
        case .iconLabel: "B · Icon + label"
        case .underline: "C · Underline tabs"
        case .pill: "D · Pill tabs"
        case .iconOnly: "E · Icon only"
        case .rail: "F · Sidebar rail"
        case .menu: "G · Inline menu"
        case .tile: "H · Tiles with totals"
        }
    }

    var note: String {
        switch self {
        case .segmented:
            "The stock macOS control. Zero custom code, instantly familiar, and it inherits system behaviour for free. Text-only, so panes read as words not glyphs, and it eats a full row of height."
        case .iconLabel:
            "What v2 ships. Icons make panes scannable once you've learned them; the accent-filled selected tile is unambiguous. Tallest of the horizontal options."
        case .underline:
            "Browser/Safari idiom. Very quiet — the bar almost disappears until you look for it, which suits a panel whose content is the point. Selection is a thin underline, so it's the least visible at a glance."
        case .pill:
            "What v1 shipped, cleaned up. Capsule fill reads clearly as 'selected' and needs less height than icon+label. Closest to a web tab bar, which is the look v2 was moving away from."
        case .iconOnly:
            "Most compact horizontal option — buys a whole row back for the panes. Costs discoverability: 'chart.pie' vs 'chart.bar' is a coin-flip until learned, so it leans on tooltips."
        case .rail:
            "Moves the switcher off the vertical budget entirely by going down the left edge. Native-feeling (Mail/Finder sidebars) but takes ~44pt of a 380pt width, and the panes are already tight."
        case .menu:
            "Cheapest by far in space — one line, and it can sit inline with the range label. But it hides the other two panes behind a click, which is bad for something you switch between constantly."
        case .tile:
            "CodexBar's provider-tile pattern: each pane carries its own headline number, so the bar is informative before you click it. Heaviest option, and the numbers compete with the summary strip above."
        }
    }
}

struct PaneSwitcher: View {
    let variant: SwitcherVariant
    @Binding var pane: Pane

    var body: some View {
        switch variant {
        case .segmented: SegmentedSwitcher(pane: $pane)
        case .iconLabel: IconLabelSwitcher(pane: $pane)
        case .underline: UnderlineSwitcher(pane: $pane)
        case .pill: PillSwitcher(pane: $pane)
        case .iconOnly: IconOnlySwitcher(pane: $pane)
        case .rail: EmptyView() // rendered beside the content, see GalleryView
        case .menu: MenuSwitcher(pane: $pane)
        case .tile: TileSwitcher(pane: $pane)
        }
    }
}

// MARK: - A · Segmented control

private struct SegmentedSwitcher: View {
    @Binding var pane: Pane

    var body: some View {
        Picker("", selection: $pane) {
            ForEach(Pane.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - B · Icon + label (what v2 ships)

private struct IconLabelSwitcher: View {
    @Binding var pane: Pane

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Pane.allCases) { candidate in
                let isOn = pane == candidate
                Button { pane = candidate } label: {
                    VStack(spacing: 3) {
                        Image(systemName: candidate.symbol)
                            .font(.system(size: 15))
                            .frame(width: 30, height: 26)
                            .background(isOn ? Color.accentColor : .clear)
                            .foregroundStyle(isOn ? Color.white : Color.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text(candidate.label)
                            .font(.caption2)
                            .foregroundStyle(isOn ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - C · Underline tabs

private struct UnderlineSwitcher: View {
    @Binding var pane: Pane

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Pane.allCases) { candidate in
                let isOn = pane == candidate
                Button { pane = candidate } label: {
                    VStack(spacing: 5) {
                        Text(candidate.label)
                            .font(.callout.weight(isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? .primary : .secondary)
                        Rectangle()
                            .fill(isOn ? Color.accentColor : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

// MARK: - D · Pill tabs (v1's, cleaned up)

private struct PillSwitcher: View {
    @Binding var pane: Pane

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Pane.allCases) { candidate in
                let isOn = pane == candidate
                Button { pane = candidate } label: {
                    Text(candidate.label)
                        .font(.callout.weight(isOn ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(isOn ? Color.accentColor : Color.primary.opacity(0.06))
                        .foregroundStyle(isOn ? Color.white : Color.secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - E · Icon only

private struct IconOnlySwitcher: View {
    @Binding var pane: Pane

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Pane.allCases) { candidate in
                let isOn = pane == candidate
                Button { pane = candidate } label: {
                    Image(systemName: candidate.symbol)
                        .font(.system(size: 14))
                        .frame(width: 34, height: 24)
                        .background(isOn ? Color.accentColor : Color.primary.opacity(0.06))
                        .foregroundStyle(isOn ? Color.white : Color.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(candidate.label)
            }
            Spacer()
            Text(pane.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

// MARK: - G · Inline menu

private struct MenuSwitcher: View {
    @Binding var pane: Pane

    var body: some View {
        HStack {
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) {
                    Label($0.label, systemImage: $0.symbol).tag($0)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Text("Aug 25 – Aug 29")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

// MARK: - H · Tiles with totals

private struct TileSwitcher: View {
    @Binding var pane: Pane

    // Each tile carries its own headline number, so the switcher is
    // informative before you click it.
    private func headline(for pane: Pane) -> String {
        switch pane {
        case .history: "12 views"
        case .byService: "4 services"
        case .trends: "5 days"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Pane.allCases) { candidate in
                let isOn = pane == candidate
                Button { pane = candidate } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Image(systemName: candidate.symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(isOn ? Color.white : Color.secondary)
                        Text(candidate.shortLabel)
                            .font(.caption2)
                            .foregroundStyle(isOn ? Color.white.opacity(0.9) : Color.secondary)
                        Text(headline(for: candidate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(isOn ? Color.accentColor : Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - F · Sidebar rail (rendered beside content, not above it)

struct RailSwitcher: View {
    @Binding var pane: Pane

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Pane.allCases) { candidate in
                let isOn = pane == candidate
                Button { pane = candidate } label: {
                    VStack(spacing: 2) {
                        Image(systemName: candidate.symbol)
                            .font(.system(size: 14))
                        Text(candidate.shortLabel)
                            .font(.system(size: 8))
                    }
                    .frame(width: 44, height: 40)
                    .background(isOn ? Color.accentColor : .clear)
                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(candidate.label)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
        .background(Color.primary.opacity(0.04))
    }
}

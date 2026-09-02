import SwiftUI

// The popover shell is deliberately a stub: enough chrome around the
// switcher that each variant is judged in context (it has to sit under a
// title row and a summary strip, and above a scrolling pane), but the pane
// content itself is placeholder — this prototype is only asking about the
// switcher.
struct SwitcherGalleryView: View {
    @State private var variant: SwitcherVariant = .segmented
    @State private var pane: Pane = .history

    private var variantIndex: Int {
        SwitcherVariant.allCases.firstIndex(of: variant) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            Divider()
            rangeRow
            Divider()
            summaryStrip
            Divider()

            if variant == .rail {
                // The rail is the one variant that isn't a horizontal bar,
                // so it's laid out beside the content instead of above it.
                HStack(spacing: 0) {
                    RailSwitcher(pane: $pane)
                    Divider()
                    paneStub
                }
            } else {
                PaneSwitcher(variant: variant, pane: $pane)
                Divider()
                paneStub
            }

            Divider()
            variantBar
        }
        .frame(width: 380, height: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text("WatchLogs").font(.headline)
            Spacer()
            Text("This Week · 13h 17m")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "gearshape").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var rangeRow: some View {
        Picker("", selection: .constant(1)) {
            Text("Today").tag(0)
            Text("This Week").tag(1)
            Text("This Month").tag(2)
            Text("Custom").tag(3)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var summaryStrip: some View {
        HStack(spacing: 16) {
            ForEach([Service.youtube, .netflix, .twitch], id: \.self) { service in
                HStack(spacing: 5) {
                    ServiceLogo(service: service, size: 14)
                    Text(MockData.formatMinutes(MockData.serviceTotals(over: 25...29)[service] ?? 0))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var paneStub: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pane.label)
                .font(.title3.weight(.semibold))
            Text("Placeholder content. This prototype only tests the switcher above — see v1 and v2 for the real panes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(0..<4, id: \.self) { i in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.10))
                            .frame(height: 9)
                            .frame(maxWidth: i.isMultiple(of: 2) ? .infinity : 180)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 120, height: 7)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    // The bottom bar mirrors prototypes/menubar-layout/index.html's
    // `#switcher`: arrows to page through variants, plus the rationale for
    // whichever one is showing.
    private var variantBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    let all = SwitcherVariant.allCases
                    variant = all[(variantIndex - 1 + all.count) % all.count]
                } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)

                Text(variant.name)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)

                Button {
                    let all = SwitcherVariant.allCases
                    variant = all[(variantIndex + 1) % all.count]
                } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)

                Text("\(variantIndex + 1)/\(SwitcherVariant.allCases.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Text(variant.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(height: 108, alignment: .top)
        .background(Color.primary.opacity(0.04))
    }
}

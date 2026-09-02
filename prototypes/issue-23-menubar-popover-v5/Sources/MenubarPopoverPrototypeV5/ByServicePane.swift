import SwiftUI

// Two grid lines run down the whole pane. Everything with an identity — a
// service logo in a header, a format mark in a breakdown row — sits in the
// icon gutter on the left; every bar starts where that gutter ends, and every
// bar stops where the time gutter begins.
//
// The second half is what makes the bars honest: the rescaling in
// `youtubeBreakdown` puts a format and its parent service on one numeric
// scale, and drawing them in an identical width is what puts them on one
// pixel scale. The first half is why the gutter is an icon and not a word —
// "videos"/"shorts"/"live" needed 40pt, which shoved the breakdown bars a
// quarter-inch right of the service bar they belong to.
private enum PlotColumn {
    // Same 15pt as the ServiceLogo in a header row, so the two kinds of mark
    // share one column rather than merely being near each other.
    static let iconWidth: CGFloat = 15
    // Wide enough for "4h 08m" at .caption. At 36 it wrapped to two lines and
    // gave the breakdown rows an uneven vertical rhythm.
    static let timeWidth: CGFloat = 52
    static let spacing: CGFloat = 8

    static let leading = iconWidth + spacing
    static let trailing = timeWidth + spacing

    // A service's formats step in by exactly `leading`, which lands their
    // marks under the first letter of the service's name rather than under
    // its logo — the cheapest way to say "these belong to YouTube" without
    // drawing a rule or a box around them.
    static let nest = leading

    // The service's own bar reclaims that step on its right end, so nesting
    // the formats doesn't quietly shorten the total they're slices of. It
    // ends past the time gutter, which is fine: nothing shares its line.
    static let barTrailing = trailing - nest

    // Every bar in the pane is MEASURED from this one line, a service's own
    // and its formats' alike, so their ends can be read off against each
    // other directly instead of by eye across a step. A service bar then
    // paints a `nest`-wide lead-in backwards out of that line, so it still
    // *looks* like it starts under the first letter of its own name — see
    // DurationBar.leadIn for what that costs.
    static let barLeading = nest + leading

    // A format bar's box is short by one step at its right end, which is the
    // step the service bar took above. Left ends already agree.
    static let formatBarDeficit = nest
}

struct ByServicePane: View {
    @Bindable var store: PopoverStore

    var body: some View {
        let range = store.resolvedRange
        let totals = range.map(MockData.serviceTotals) ?? [:]
        let grand = max(totals.values.reduce(0, +), 1)

        VStack(alignment: .leading, spacing: 0) {
            ForEach([Service.youtube, .netflix, .twitch], id: \.self) { service in
                let minutes = totals[service] ?? 0
                if minutes > 0 {
                    ServiceRow(store: store, service: service, minutes: minutes, grand: grand)
                }
            }

            let otherMinutes = totals[.other] ?? 0
            if otherMinutes > 0 {
                AdapterSection(store: store, otherMinutes: otherMinutes, grand: grand, barHeight: BarMetrics.pane)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ServiceRow: View {
    @Bindable var store: PopoverStore
    let service: Service
    let minutes: Int
    let grand: Int

    var body: some View {
        let frac = Double(minutes) / Double(grand)
        let expandable = service == .youtube

        // Roomier than the 6/8 this used with a stock ProgressView: a 3pt
        // bar gives back height the row was using, and without spending it
        // again on spacing the service rows just pack tighter together.
        VStack(alignment: .leading, spacing: 8) {
            // Only YouTube has a breakdown to open, so only YouTube's header
            // is a Button. The rest render as plain rows rather than disabled
            // Buttons: `.disabled` dims a button's whole label, which greyed
            // out the logo, name and totals on every service except YouTube
            // and made them read as unavailable.
            if expandable {
                // The whole header row toggles, not just the chevron.
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { store.youtubeExpanded.toggle() }
                } label: {
                    header(frac: frac, showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                header(frac: frac, showsChevron: false)
            }

            DurationBar(
                fraction: frac,
                height: BarMetrics.pane,
                tint: service.color,
                showsTrack: false,
                leadIn: PlotColumn.nest
            )
            .padding(.leading, PlotColumn.barLeading)
            .padding(.trailing, PlotColumn.barTrailing)

            if expandable && store.youtubeExpanded {
                youtubeBreakdown
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func header(frac: Double, showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            ServiceLogo(service: service, size: PlotColumn.iconWidth)
            Text(service.name).font(.callout.weight(.medium))
            Spacer(minLength: 8)
            Text("\(Int((frac * 100).rounded()))%")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(MockData.formatMinutes(minutes))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(store.youtubeExpanded ? 90 : 0))
            }
        }
        .contentShape(Rectangle())
    }

    private var youtubeBreakdown: some View {
        // Each format's own share (0.66/0.28/0.06) is relative to YouTube's
        // total, so left as-is "66% of YouTube" and "55% of everything" would
        // both just read as "a bar" and a format could stretch past the total
        // it's a slice of. Rescaling every format to a share of the grand
        // total — the same scale the parent bar uses — makes every format bar
        // strictly shorter than YouTube's, since a share of a share can't
        // exceed the whole. That only holds because both are now drawn in the
        // same PlotColumn width: while the format bars sat in a narrower box,
        // "two thirds of YouTube" still rendered at half of YouTube's bar.
        let parentFrac = Double(minutes) / Double(grand)

        // Roomier than the 6 these sat at: three rows of mark-plus-hairline
        // packed that tightly read as one texture, and the point of the
        // breakdown is that you can weigh the three against each other.
        return VStack(alignment: .leading, spacing: 9) {
            ForEach(MockData.youtubeSplit, id: \.format) { split in
                breakdownBar(
                    format: split.format,
                    minutes: Int(Double(minutes) * split.frac),
                    fracOfGrand: parentFrac * split.frac,
                    tint: service.color.opacity(0.6)
                )
            }
        }
        .padding(.leading, PlotColumn.nest)
        .padding(.top, 6)
    }

    // One line per format: mark, bar, and minutes side by side — not label
    // over bar over minutes. The mark sits flush left, directly under the
    // service logo, so a format reads as another row of the same column
    // rather than as a paragraph nested under "YouTube."
    private func breakdownBar(format: ContentFormat, minutes: Int, fracOfGrand: Double, tint: Color) -> some View {
        HStack(spacing: PlotColumn.spacing) {
            // The mark carries the name now, so the name has to live
            // somewhere recoverable: hover any row to read it back.
            FormatLogo(format: format, size: PlotColumn.iconWidth)
                .help(format.name)
            DurationBar(
                fraction: fracOfGrand,
                height: BarMetrics.pane,
                tint: tint,
                showsTrack: false,
                narrowerThanPlotBy: PlotColumn.formatBarDeficit
            )
            Text(MockData.formatMinutes(minutes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: PlotColumn.timeWidth, alignment: .trailing)
        }
    }
}

private struct AdapterSection: View {
    @Bindable var store: PopoverStore
    let otherMinutes: Int
    let grand: Int
    let barHeight: CGFloat

    var body: some View {
        let frac = Double(otherMinutes) / Double(grand)

        VStack(alignment: .leading, spacing: 8) {
            // Same toggle pattern as YouTube's breakdown: the header opens
            // the per-site list nested under it, instead of that list always
            // sitting loose below the row it belongs to.
            Button {
                withAnimation(.easeOut(duration: 0.15)) { store.otherExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    ServiceLogo(service: .other, size: PlotColumn.iconWidth)
                    Text("Others").font(.callout.weight(.medium))
                    Spacer(minLength: 8)
                    Text("\(Int((frac * 100).rounded()))%").font(.caption).foregroundStyle(.tertiary)
                    Text(MockData.formatMinutes(otherMinutes)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(store.otherExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Full-bleed here, this bar was measured against a wider box than
            // the service bars above it, so Others' 8% read as longer than it is.
            DurationBar(
                fraction: frac,
                height: barHeight,
                tint: Service.other.color,
                showsTrack: false,
                leadIn: PlotColumn.nest
            )
            .padding(.leading, PlotColumn.barLeading)
            .padding(.trailing, PlotColumn.barTrailing)

            if store.otherExpanded {
                adapterList
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var adapterList: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(MockData.needsAdapter, id: \.name) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Label(entry.name, systemImage: "questionmark.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(MockData.formatMinutes(Int(Double(otherMinutes) * entry.share)))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Text(entry.note).font(.caption2).foregroundStyle(.tertiary).padding(.leading, 22)
                }
            }
        }
        .padding(.leading, PlotColumn.nest)
        .padding(.top, 4)
    }
}

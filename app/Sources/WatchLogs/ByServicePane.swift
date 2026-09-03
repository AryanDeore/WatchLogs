import SwiftUI
import WatchLogsKit

/// Two grid lines run down the whole pane. Anything with an identity (a
/// service logo, a format mark) sits in the icon gutter on the left; every
/// bar starts where that gutter ends and stops where the time gutter begins.
///
/// That single ruler is what makes the bars honest: a service bar and its
/// format bars are drawn against the same width, so a format's length can be
/// compared directly against the total it's a slice of. Before this, a format
/// that was two-thirds of YouTube drew at half of YouTube's bar because the
/// two sat in boxes of different widths.
private enum PlotColumn {
    static let iconWidth: CGFloat = 15
    static let timeWidth: CGFloat = 52
    static let spacing: CGFloat = 8

    static let leading = iconWidth + spacing
    static let trailing = timeWidth + spacing

    /// A service's formats step in by exactly `leading`, which lands their
    /// marks under the first letter of the service's name.
    static let nest = leading

    /// The service's own bar reclaims that step on its right end, so nesting
    /// the formats doesn't quietly shorten the total they're slices of.
    static let barTrailing = trailing - nest

    /// Every bar in the pane is measured from this one line so their right
    /// ends can be read against each other directly instead of by eye.
    static let barLeading = nest + leading

    /// A format bar's box is short by one step at its right end (the step the
    /// service bar took above). Left ends already agree.
    static let formatBarDeficit = nest
}

struct ByServicePane: View {
    let model: MenubarPopoverReadModel
    let data: MenubarPopoverData

    var body: some View {
        let grand = max(data.total.watchedMs, 1)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(data.services.filter { $0.service != .otherSites }) { service in
                if service.totals.watchedMs > 0 {
                    ServiceRow(model: model, service: service, grand: grand)
                }
            }

            if let other = data.services.first(where: { $0.service == .otherSites }), other.totals.watchedMs > 0 {
                OtherSitesSection(model: model, other: other, grand: grand)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ServiceRow: View {
    let model: MenubarPopoverReadModel
    let service: ServiceDisplayBucketTotal
    let grand: Int

    var body: some View {
        let frac = Double(service.totals.watchedMs) / Double(grand)
        let expandable = service.service == .youtube

        VStack(alignment: .leading, spacing: 8) {
            // Only YouTube has a breakdown to open, so only YouTube's header
            // is a Button. Plain rows for the rest: `.disabled` dims a
            // button's whole label and greys out the logo, name, and totals.
            if expandable {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { model.youtubeExpanded.toggle() }
                } label: {
                    header(frac: frac, showsChevron: true, isOpen: model.youtubeExpanded)
                }
                .buttonStyle(.plain)
            } else {
                header(frac: frac, showsChevron: false, isOpen: false)
            }

            DurationBar(
                fraction: frac,
                height: BarMetrics.pane,
                tint: bucketColor(service.service),
                showsTrack: false,
                leadIn: PlotColumn.nest
            )
            .padding(.leading, PlotColumn.barLeading)
            .padding(.trailing, PlotColumn.barTrailing)

            if expandable && model.youtubeExpanded {
                youtubeBreakdown
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func header(frac: Double, showsChevron: Bool, isOpen: Bool) -> some View {
        HStack(spacing: 8) {
            ServiceLogo(service: service.service, size: PlotColumn.iconWidth)
            Text(service.service.name).font(.callout.weight(.medium))
            Spacer(minLength: 8)
            Text("\(Int((frac * 100).rounded()))%")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(formatWatchedTime(milliseconds: service.totals.watchedMs))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
        }
        .contentShape(Rectangle())
    }

    /// Format bars use the parent service's *share of the grand total*, not
    /// their share of the service, so every bar in the pane is measured on the
    /// same scale and a format bar can never render longer than the service
    /// it's a slice of.
    private var youtubeBreakdown: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(service.formats.sorted { $0.totals.watchedMs > $1.totals.watchedMs }, id: \.contentFormat) { split in
                if let format = ContentFormat(label: split.contentFormat) {
                    breakdownBar(
                        format: format,
                        minutesMs: split.totals.watchedMs,
                        fracOfGrand: Double(split.totals.watchedMs) / Double(grand),
                        tint: bucketColor(service.service).opacity(0.6)
                    )
                }
            }
            if service.embeddedWatchedMs > 0 {
                embeddedRow(
                    milliseconds: service.embeddedWatchedMs,
                    fracOfGrand: Double(service.embeddedWatchedMs) / Double(grand)
                )
            }
        }
        .padding(.leading, PlotColumn.nest)
        .padding(.top, 6)
    }

    private func breakdownBar(format: ContentFormat, minutesMs: Int, fracOfGrand: Double, tint: Color) -> some View {
        HStack(spacing: PlotColumn.spacing) {
            FormatLogo(format: format, size: PlotColumn.iconWidth)
                .help(format.name)
            DurationBar(
                fraction: fracOfGrand,
                height: BarMetrics.pane,
                tint: tint,
                showsTrack: false,
                narrowerThanPlotBy: PlotColumn.formatBarDeficit
            )
            Text(formatWatchedTime(milliseconds: minutesMs))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: PlotColumn.timeWidth, alignment: .trailing)
        }
    }

    private func embeddedRow(milliseconds: Int, fracOfGrand: Double) -> some View {
        HStack(spacing: PlotColumn.spacing) {
            Image(systemName: "square.on.square")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: PlotColumn.iconWidth)
                .help("Embedded in a third-party page")
            DurationBar(
                fraction: fracOfGrand,
                height: BarMetrics.pane,
                tint: Color.orange.opacity(0.6),
                showsTrack: false,
                narrowerThanPlotBy: PlotColumn.formatBarDeficit
            )
            Text(formatWatchedTime(milliseconds: milliseconds))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: PlotColumn.timeWidth, alignment: .trailing)
        }
    }
}

private struct OtherSitesSection: View {
    let model: MenubarPopoverReadModel
    let other: ServiceDisplayBucketTotal
    let grand: Int

    var body: some View {
        let frac = Double(other.totals.watchedMs) / Double(grand)

        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { model.otherExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    ServiceLogo(service: .otherSites, size: PlotColumn.iconWidth)
                    Text("Other sites").font(.callout.weight(.medium))
                    Spacer(minLength: 8)
                    Text("\(Int((frac * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(formatWatchedTime(milliseconds: other.totals.watchedMs))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(model.otherExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            DurationBar(
                fraction: frac,
                height: BarMetrics.pane,
                tint: bucketColor(.otherSites),
                showsTrack: false,
                leadIn: PlotColumn.nest
            )
            .padding(.leading, PlotColumn.barLeading)
            .padding(.trailing, PlotColumn.barTrailing)

            if model.otherExpanded {
                adapterList
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var adapterList: some View {
        // Each format slice inside `Other sites` names an actual service —
        // twitch, vimeo, and the like — so a per-service list falls straight
        // out of the rollup grain.
        let bySite = Dictionary(grouping: other.formats, by: \.service)
            .map { (site: $0.key, watchedMs: $0.value.reduce(0) { $0 + $1.totals.watchedMs }) }
            .sorted { $0.watchedMs > $1.watchedMs }

        return VStack(alignment: .leading, spacing: 9) {
            ForEach(bySite, id: \.site) { entry in
                HStack {
                    Label(entry.site, systemImage: "questionmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(formatWatchedTime(milliseconds: entry.watchedMs))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.leading, PlotColumn.nest)
        .padding(.top, 4)
    }
}

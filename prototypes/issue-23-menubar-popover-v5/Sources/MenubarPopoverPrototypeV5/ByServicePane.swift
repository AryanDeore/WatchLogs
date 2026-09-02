import SwiftUI

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
                    Divider().padding(.horizontal, 14)
                }
            }

            let otherMinutes = totals[.other] ?? 0
            if otherMinutes > 0 {
                AdapterSection(otherMinutes: otherMinutes, grand: grand, barHeight: BarMetrics.pane)
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

            DurationBar(fraction: frac, height: BarMetrics.pane, tint: service.color)

            if expandable && store.youtubeExpanded {
                youtubeBreakdown
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func header(frac: Double, showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            ServiceLogo(service: service, size: 15)
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
        // Embedded is one more bar in the same list rather than a footnote —
        // and it only earns a row once there's more than a minute of it. It
        // shares the other formats' tint too: it's still YouTube time, and
        // its own orange read as a warning next to three red siblings. The
        // "embedded" label carries the distinction on its own.
        let embeddedMinutes = Int(Double(minutes) * MockData.youtubeEmbeddedFrac)

        return VStack(alignment: .leading, spacing: 9) {
            ForEach(MockData.youtubeSplit, id: \.label) { split in
                breakdownBar(
                    label: split.label,
                    minutes: Int(Double(minutes) * split.frac),
                    frac: split.frac,
                    tint: service.color.opacity(0.6)
                )
            }
            if embeddedMinutes > 1 {
                breakdownBar(
                    label: "embedded",
                    minutes: embeddedMinutes,
                    frac: MockData.youtubeEmbeddedFrac,
                    tint: service.color.opacity(0.6)
                )
            }
        }
        .padding(.leading, 22)
        .padding(.top, 4)
    }

    private func breakdownBar(label: String, minutes: Int, frac: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(MockData.formatMinutes(minutes))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            DurationBar(fraction: frac, height: BarMetrics.pane, tint: tint)
        }
    }
}

private struct AdapterSection: View {
    let otherMinutes: Int
    let grand: Int
    let barHeight: CGFloat

    var body: some View {
        let frac = Double(otherMinutes) / Double(grand)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ServiceLogo(service: .other, size: 15)
                Text("All other sites").font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Text("\(Int((frac * 100).rounded()))%").font(.caption).foregroundStyle(.tertiary)
                Text(MockData.formatMinutes(otherMinutes)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            DurationBar(fraction: frac, height: barHeight, tint: Service.other.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        Divider().padding(.horizontal, 14)

        ForEach(MockData.needsAdapter, id: \.name) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label(entry.name, systemImage: "questionmark.circle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(MockData.formatMinutes(Int(Double(otherMinutes) * entry.share)))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(entry.note).font(.caption2).foregroundStyle(.tertiary).padding(.leading, 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            Divider().padding(.horizontal, 14)
        }
    }
}

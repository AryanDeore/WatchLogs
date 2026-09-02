import SwiftUI

struct ByServicePane: View {
    @Bindable var store: PopoverStore

    var body: some View {
        let range = store.resolvedRange
        let totals = range.map(MockData.serviceTotals) ?? [:]
        let grand = max(totals.values.reduce(0, +), 1)

        VStack(alignment: .leading, spacing: 0) {
            Text("Share of watched time · \(store.range.label) · \(MockData.rangeResolvedLabel(range)) · \(MockData.formatMinutes(grand)) total")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 6)

            ForEach([Service.youtube, .netflix, .twitch], id: \.self) { service in
                let minutes = totals[service] ?? 0
                if minutes > 0 {
                    ServiceRow(store: store, service: service, minutes: minutes, grand: grand)
                    Divider().padding(.leading, 14)
                }
            }

            let otherMinutes = totals[.other] ?? 0
            if otherMinutes > 0 {
                AdapterSection(otherMinutes: otherMinutes, grand: grand)
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

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label {
                    Text(service.name).font(.callout.weight(.medium))
                } icon: {
                    Image(systemName: service.symbol).foregroundStyle(service.color)
                }
                Spacer()
                Text("\(Int((frac * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(MockData.formatMinutes(minutes))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if expandable {
                    Button {
                        store.youtubeExpanded.toggle()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .rotationEffect(.degrees(store.youtubeExpanded ? 90 : 0))
                    }
                    .buttonStyle(.borderless)
                }
            }
            ProgressView(value: frac).tint(service.color)

            if expandable && store.youtubeExpanded {
                youtubeBreakdown
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var youtubeBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(MockData.youtubeSplit, id: \.label) { split in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(split.label).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(MockData.formatMinutes(Int(Double(minutes) * split.frac)))
                            .font(.caption).monospacedDigit()
                    }
                    ProgressView(value: split.frac).tint(service.color.opacity(0.6))
                }
            }
            HStack {
                Text("— of which embedded").font(.caption2).foregroundStyle(.orange)
                Spacer()
                Text(MockData.formatMinutes(Int(Double(minutes) * MockData.youtubeEmbeddedFrac)))
                    .font(.caption2).foregroundStyle(.orange).monospacedDigit()
            }
        }
        .padding(.leading, 22)
        .padding(.top, 2)
    }
}

private struct AdapterSection: View {
    let otherMinutes: Int
    let grand: Int

    var body: some View {
        let frac = Double(otherMinutes) / Double(grand)

        VStack(alignment: .leading, spacing: 2) {
            Label("Other sites — need an Adapter", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text("\(Int((frac * 100).rounded()))% of the range · \(MockData.formatMinutes(otherMinutes)). Counted, but metadata is thin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text("All other sites").font(.callout.weight(.medium))
                } icon: {
                    Image(systemName: Service.other.symbol).foregroundStyle(Service.other.color)
                }
                Spacer()
                Text("\(Int((frac * 100).rounded()))%").font(.caption).foregroundStyle(.tertiary)
                Text(MockData.formatMinutes(otherMinutes)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: frac).tint(Service.other.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        Divider().padding(.leading, 14)

        ForEach(MockData.needsAdapter, id: \.name) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label(entry.name, systemImage: "questionmark.circle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(MockData.formatMinutes(Int(Double(otherMinutes) * entry.share)))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(entry.note).font(.caption2).foregroundStyle(.tertiary).padding(.leading, 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            Divider().padding(.leading, 14)
        }
    }
}

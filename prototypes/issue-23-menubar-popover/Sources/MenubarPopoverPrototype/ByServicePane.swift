import SwiftUI

struct ByServicePane: View {
    @Bindable var store: PopoverStore

    var body: some View {
        let range = store.resolvedRange
        let totals = range.map(MockData.serviceTotals) ?? [:]
        let grand = max(totals.values.reduce(0, +), 1)

        VStack(alignment: .leading, spacing: 0) {
            Text("Share of watched time · \(store.range.label) · \(MockData.rangeResolvedLabel(range)) · \(MockData.formatMinutes(grand)) total")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach([Service.youtube, .netflix, .twitch], id: \.self) { service in
                let minutes = totals[service] ?? 0
                if minutes > 0 {
                    serviceRow(service, minutes: minutes, grand: grand)
                }
            }

            let otherMinutes = totals[.other] ?? 0
            if otherMinutes > 0 {
                adapterSection(otherMinutes: otherMinutes, grand: grand)
            }
        }
    }

    @ViewBuilder
    private func serviceRow(_ service: Service, minutes: Int, grand: Int) -> some View {
        let frac = Double(minutes) / Double(grand)
        let expandable = service == .youtube
        let expanded = expandable && store.youtubeExpanded

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if expandable {
                    Button {
                        store.youtubeExpanded.toggle()
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12)
                }
                Text(service.mono)
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 15, height: 15)
                    .background(service.color)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(service.name).fontWeight(.semibold)
                Spacer()
                Text("\(Int((frac * 100).rounded()))%")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(MockData.formatMinutes(minutes))
                    .font(.system(size: 12, design: .monospaced))
            }

            partToWholeBar(frac: frac, color: service.color)

            if expanded {
                youtubeBreakdown(totalMinutes: minutes)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(Divider(), alignment: .bottom)
    }

    private func partToWholeBar(frac: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .separatorColor).opacity(0.5))
                RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.85))
                    .frame(width: geo.size.width * frac)
            }
        }
        .frame(height: 7)
    }

    private func youtubeBreakdown(totalMinutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(MockData.youtubeSplit, id: \.label) { split in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(split.label).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(MockData.formatMinutes(Int(Double(totalMinutes) * split.frac)))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .separatorColor).opacity(0.5))
                            RoundedRectangle(cornerRadius: 3).fill(Service.youtube.color.opacity(0.5))
                                .frame(width: geo.size.width * split.frac)
                        }
                    }
                    .frame(height: 4)
                }
            }
            HStack {
                Text("— of which embedded").font(.system(size: 10.5)).foregroundStyle(.orange)
                Spacer()
                Text(MockData.formatMinutes(Int(Double(totalMinutes) * MockData.youtubeEmbeddedFrac)))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.orange)
            }
            .padding(.top, 4)
            .overlay(Divider().opacity(0.6), alignment: .top)
        }
        .padding(.leading, 23)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func adapterSection(otherMinutes: Int, grand: Int) -> some View {
        let frac = Double(otherMinutes) / Double(grand)

        Label("OTHER SITES — NEED AN ADAPTER", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)

        Text("\(Int((frac * 100).rounded()))% of the range · \(MockData.formatMinutes(otherMinutes)). Counted, but metadata is thin.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 12)
                Text("•")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 15, height: 15)
                    .background(Service.other.color)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("All other sites").fontWeight(.semibold)
                Spacer()
                Text("\(Int((frac * 100).rounded()))%")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(MockData.formatMinutes(otherMinutes))
                    .font(.system(size: 12, design: .monospaced))
            }
            partToWholeBar(frac: frac, color: Service.other.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(Divider(), alignment: .bottom)

        ForEach(MockData.needsAdapter, id: \.name) { entry in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 12)
                    Text("•")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 15, height: 15)
                        .background(Service.other.color.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(entry.name).fontWeight(.semibold)
                    Spacer()
                    Text(MockData.formatMinutes(Int(Double(otherMinutes) * entry.share)))
                        .font(.system(size: 12, design: .monospaced))
                }
                Text(entry.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 23)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(Divider(), alignment: .bottom)
        }
    }
}

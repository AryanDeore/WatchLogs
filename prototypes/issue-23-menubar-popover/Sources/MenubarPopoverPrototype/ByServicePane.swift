import SwiftUI

struct ByServicePane: View {
    @Bindable var store: PopoverStore

    var body: some View {
        let range = store.resolvedRange
        let totals = range.map(MockData.serviceTotals) ?? [:]
        let grand = max(totals.values.reduce(0, +), 1)

        VStack(alignment: .leading, spacing: 0) {
            (Text("Share of watched time · ") + Text(store.range.label).foregroundStyle(Theme.ink).fontWeight(.semibold) + Text(" · \(MockData.rangeResolvedLabel(range)) · \(MockData.formatMinutes(grand)) total"))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkDim)
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
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 12)
                } else {
                    Color.clear.frame(width: 12)
                }
                Text(service.mono)
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 15, height: 15)
                    .background(service.color)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(service.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int((frac * 100).rounded()))%")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
                Text(MockData.formatMinutes(minutes))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }

            partToWholeBar(frac: frac, color: service.color)

            if expanded {
                youtubeBreakdown(totalMinutes: minutes)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }

    private func partToWholeBar(frac: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.panel2)
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
                        Text(split.label).font(.system(size: 11)).foregroundStyle(Theme.inkDim)
                        Spacer()
                        Text(MockData.formatMinutes(Int(Double(totalMinutes) * split.frac)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.panel2)
                            RoundedRectangle(cornerRadius: 3).fill(Theme.yt.opacity(0.5))
                                .frame(width: geo.size.width * split.frac)
                        }
                    }
                    .frame(height: 4)
                }
            }
            HStack {
                Text("— of which embedded").font(.system(size: 10.5)).foregroundStyle(Theme.warn)
                Spacer()
                Text(MockData.formatMinutes(Int(Double(totalMinutes) * MockData.youtubeEmbeddedFrac)))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.warn)
            }
            .padding(.top, 4)
            .overlay(Rectangle().fill(Theme.line2).frame(height: 1), alignment: .top)
        }
        .padding(.leading, 23)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func adapterSection(otherMinutes: Int, grand: Int) -> some View {
        let frac = Double(otherMinutes) / Double(grand)

        HStack(spacing: 7) {
            Text("⚠").font(.system(size: 11, weight: .bold))
            Text("OTHER SITES — NEED AN ADAPTER")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
        }
        .foregroundStyle(Theme.warn)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)

        Text("\(Int((frac * 100).rounded()))% of the range · \(MockData.formatMinutes(otherMinutes)). Counted, but metadata is thin.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkDim)
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 12)
                Text("•")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 15, height: 15)
                    .background(Theme.other)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("All other sites").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int((frac * 100).rounded()))%")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
                Text(MockData.formatMinutes(otherMinutes))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }
            partToWholeBar(frac: frac, color: Theme.other)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)

        ForEach(MockData.needsAdapter, id: \.name) { entry in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 12)
                    Text("•")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 15, height: 15)
                        .background(Theme.other.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(entry.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(MockData.formatMinutes(Int(Double(otherMinutes) * entry.share)))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                }
                Text(entry.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.leading, 23)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
        }
    }
}

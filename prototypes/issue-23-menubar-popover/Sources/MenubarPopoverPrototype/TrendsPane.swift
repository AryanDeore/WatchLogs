import SwiftUI

struct TrendsPane: View {
    @Bindable var store: PopoverStore

    var body: some View {
        let range = store.resolvedRange
        let days = range.map(Array.init) ?? []

        VStack(alignment: .leading, spacing: 10) {
            (Text("Watched time per day · ") + Text(store.range.label).foregroundStyle(Theme.ink) + Text(" · \(MockData.rangeResolvedLabel(range))"))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkDim)

            if days.count <= 1 {
                singleDayMix(day: days.first)
            } else if days.count <= 14 {
                horizontalBars(days: days)
            } else {
                verticalColumns(days: days)
            }

            legend
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(Service.allCases) { service in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(service.color).frame(width: 9, height: 9)
                    Text(service.name).font(.system(size: 10.5)).foregroundStyle(Theme.inkDim)
                }
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func singleDayMix(day: Int?) -> some View {
        Text("A single day has no trend — here's \(day == MockData.today ? "today" : "the day")'s mix:")
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.inkFaint)

        let minutes = day.flatMap { MockData.daily[$0] } ?? [:]
        let entries = Service.allCases.compactMap { s -> (Service, Int)? in
            let m = minutes[s] ?? 0
            return m > 0 ? (s, m) : nil
        }
        if entries.isEmpty {
            Text("nothing watched yet").font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint)
        } else {
            VStack(spacing: 6) {
                ForEach(entries, id: \.0) { service, mins in
                    trendRow(label: service.name, minutes: mins, maxMinutes: mins, segments: [(service, mins)])
                }
            }
        }
    }

    private func horizontalBars(days: [Int]) -> some View {
        let maxDay = max(days.map(MockData.dayTotal).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("bar length ∝ watch time · longest day = \(MockData.formatMinutes(maxDay))")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.inkFaint)
            VStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let total = MockData.dayTotal(day)
                    let segments = Service.allCases.compactMap { s -> (Service, Int)? in
                        let m = (MockData.daily[day] ?? [:])[s] ?? 0
                        return m > 0 ? (s, m) : nil
                    }
                    trendRow(label: "\(MockData.weekdayName[day] ?? "Aug") \(day)", minutes: total, maxMinutes: maxDay, segments: segments)
                }
            }
            Text("Horizontal — \(days.count) days (≤ 14).")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkFaint)
        }
    }

    private func trendRow(label: String, minutes: Int, maxMinutes: Int, segments: [(Service, Int)]) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 52, alignment: .trailing)
            ZStack {
                if segments.isEmpty {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.panel2)
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(segments, id: \.0) { service, mins in
                                Rectangle()
                                    .fill(service.color.opacity(0.9))
                                    .frame(width: geo.size.width * (Double(mins) / Double(maxMinutes)))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(height: 15)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.panel2))
            Text(minutes > 0 ? MockData.formatMinutes(minutes) : "–")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
                .frame(width: 52, alignment: .leading)
        }
    }

    private func verticalColumns(days: [Int]) -> some View {
        let maxDay = max(days.map(MockData.dayTotal).max() ?? 1, 1)
        let height: CGFloat = 150
        let dense = days.count > 20
        return VStack(alignment: .leading, spacing: 4) {
            Text("top of chart = \(MockData.formatMinutes(maxDay))")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.inkFaint)
            HStack(alignment: .bottom, spacing: dense ? 2 : 4) {
                ForEach(days, id: \.self) { day in
                    let minutes = MockData.daily[day] ?? [:]
                    VStack(spacing: 0) {
                        ForEach(Service.allCases.reversed()) { service in
                            let m = minutes[service] ?? 0
                            if m > 0 {
                                Rectangle()
                                    .fill(service.color.opacity(0.9))
                                    .frame(height: height * (Double(m) / Double(maxDay)))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height, alignment: .bottom)
            .overlay(Rectangle().fill(Theme.line2).frame(height: 1), alignment: .bottom)
            HStack(spacing: dense ? 2 : 4) {
                ForEach(days.indices, id: \.self) { i in
                    let day = days[i]
                    Text(i % 5 == 0 || day == MockData.today ? "\(day)" : "")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.inkFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("Vertical — \(days.count) days (> 14). One column per day, labels every 5th.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkFaint)
        }
    }
}

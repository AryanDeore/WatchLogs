import Charts
import SwiftUI

// Swift Charts was tried here first and pulled back out for the ≤14-day
// case: at popover width its categorical y-axis labels overlapped the bars,
// the plot border and gridlines added clutter a 380pt panel can't afford,
// and a "minutes" x-axis is less readable than just printing "3h 32m" at
// the end of each row. v1's hand-rolled layout — fixed label column,
// full-width track, value column — stayed cleaner, so it's restored here
// with native type and colors.
//
// The >14-day case keeps Swift Charts: at that density individual rows stop
// being readable anyway, and the framework's axis thinning is worth having.
struct TrendsPane: View {
    @Bindable var store: PopoverStore

    var body: some View {
        let range = store.resolvedRange
        let days = range.map(Array.init) ?? []

        VStack(alignment: .leading, spacing: 10) {
            Text("Watched time per day · \(store.range.label) · \(MockData.rangeResolvedLabel(range))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if days.count <= 1 {
                singleDayMix(day: days.first)
            } else if days.count <= 14 {
                horizontalBars(days: days)
            } else {
                verticalChart(days: days)
            }

            legend
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(Service.allCases) { service in
                HStack(spacing: 4) {
                    Circle().fill(service.color).frame(width: 7, height: 7)
                    Text(service.name).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func singleDayMix(day: Int?) -> some View {
        let minutes = day.flatMap { MockData.daily[$0] } ?? [:]
        let entries = Service.allCases.compactMap { s -> (Service, Int)? in
            let m = minutes[s] ?? 0
            return m > 0 ? (s, m) : nil
        }
        Text("A single day has no trend — here's \(day == MockData.today ? "today" : "the day")'s mix:")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        if entries.isEmpty {
            Text("Nothing watched yet").font(.caption).foregroundStyle(.tertiary)
        } else {
            let maxMinutes = entries.map(\.1).max() ?? 1
            VStack(spacing: 6) {
                ForEach(entries, id: \.0) { service, mins in
                    TrendRow(
                        label: service.name,
                        total: mins,
                        segments: [(service, mins)],
                        scaleMax: maxMinutes
                    )
                }
            }
        }
    }

    private func horizontalBars(days: [Int]) -> some View {
        let maxDay = max(days.map(MockData.dayTotal).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Bar length ∝ watch time · longest day = \(MockData.formatMinutes(maxDay))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let segments = Service.allCases.compactMap { s -> (Service, Int)? in
                        let m = (MockData.daily[day] ?? [:])[s] ?? 0
                        return m > 0 ? (s, m) : nil
                    }
                    TrendRow(
                        label: "\(MockData.weekdayName[day] ?? "Aug") \(day)",
                        total: MockData.dayTotal(day),
                        segments: segments,
                        scaleMax: maxDay
                    )
                }
            }
            Text("Horizontal — \(days.count) days (≤ 14).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func verticalChart(days: [Int]) -> some View {
        struct DataPoint: Identifiable {
            let id = UUID()
            let day: Int
            let service: Service
            let minutes: Int
        }
        let points = days.flatMap { day in
            Service.allCases.compactMap { service -> DataPoint? in
                let m = (MockData.daily[day] ?? [:])[service] ?? 0
                return m > 0 ? DataPoint(day: day, service: service, minutes: m) : nil
            }
        }
        let colorScale: KeyValuePairs<String, Color> = [
            Service.youtube.name: Service.youtube.color,
            Service.netflix.name: Service.netflix.color,
            Service.twitch.name: Service.twitch.color,
            Service.other.name: Service.other.color,
        ]
        return VStack(alignment: .leading, spacing: 4) {
            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.day),
                    y: .value("Minutes", point.minutes)
                )
                .foregroundStyle(by: .value("Service", point.service.name))
            }
            .chartForegroundStyleScale(colorScale)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let minutes = value.as(Int.self) {
                            Text("\(minutes / 60)h").font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 160)
            Text("Vertical — \(days.count) days (> 14). One column per day.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// Fixed label column · full-width stacked track · value column. The track
// always spans the same width so days are comparable at a glance, and an
// empty day reads as an empty track rather than a missing row.
private struct TrendRow: View {
    let label: String
    let total: Int
    let segments: [(Service, Int)]
    let scaleMax: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    HStack(spacing: 0) {
                        ForEach(segments, id: \.0) { service, mins in
                            Rectangle()
                                .fill(service.color)
                                .frame(width: geo.size.width * (Double(mins) / Double(scaleMax)))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)

            Text(total > 0 ? MockData.formatMinutes(total) : "—")
                .font(.caption)
                .foregroundStyle(total > 0 ? .secondary : .tertiary)
                .monospacedDigit()
                .frame(width: 52, alignment: .leading)
        }
    }
}

import Charts
import SwiftUI

// v1 hand-rolled the stacked/segmented bars with GeometryReader. Swift
// Charts (native since macOS 13, first-party — Screen Time, Fitness, Stocks
// all use it) does stacked BarMarks, axis thinning on dense data, and a
// legend for free, so this leans on that instead.
struct TrendsPane: View {
    @Bindable var store: PopoverStore

    private struct DataPoint: Identifiable {
        let id = UUID()
        let day: Int
        let service: Service
        let minutes: Int
    }

    private func dataPoints(for days: [Int]) -> [DataPoint] {
        days.flatMap { day in
            Service.allCases.compactMap { service -> DataPoint? in
                let m = (MockData.daily[day] ?? [:])[service] ?? 0
                return m > 0 ? DataPoint(day: day, service: service, minutes: m) : nil
            }
        }
    }

    private var colorScale: KeyValuePairs<String, Color> {
        [
            Service.youtube.name: Service.youtube.color,
            Service.netflix.name: Service.netflix.color,
            Service.twitch.name: Service.twitch.color,
            Service.other.name: Service.other.color,
        ]
    }

    var body: some View {
        let range = store.resolvedRange
        let days = range.map(Array.init) ?? []

        VStack(alignment: .leading, spacing: 10) {
            Text("Watched time per day · \(store.range.label) · \(MockData.rangeResolvedLabel(range))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if days.count <= 1 {
                singleDayChart(day: days.first)
            } else if days.count <= 14 {
                horizontalChart(days: days)
            } else {
                verticalChart(days: days)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func singleDayChart(day: Int?) -> some View {
        let minutes = day.flatMap { MockData.daily[$0] } ?? [:]
        let points = Service.allCases.compactMap { s -> DataPoint? in
            let m = minutes[s] ?? 0
            return day.flatMap { m > 0 ? DataPoint(day: $0, service: s, minutes: m) : nil }
        }
        Text("A single day has no trend — here's \(day == MockData.today ? "today" : "the day")'s mix:")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        if points.isEmpty {
            Text("Nothing watched yet").font(.caption).foregroundStyle(.tertiary)
        } else {
            Chart(points) { point in
                BarMark(
                    x: .value("Minutes", point.minutes),
                    y: .value("Service", point.service.name)
                )
                .foregroundStyle(by: .value("Service", point.service.name))
                .annotation(position: .trailing) {
                    Text(MockData.formatMinutes(point.minutes)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartForegroundStyleScale(colorScale)
            .chartLegend(.hidden)
            .frame(height: CGFloat(points.count) * 26 + 10)
        }
    }

    private func horizontalChart(days: [Int]) -> some View {
        let points = dataPoints(for: days)
        let labels = days.map { "\(MockData.weekdayName[$0] ?? "Aug") \($0)" }
        return VStack(alignment: .leading, spacing: 4) {
            Chart(points) { point in
                BarMark(
                    x: .value("Minutes", point.minutes),
                    y: .value("Day", "\(MockData.weekdayName[point.day] ?? "Aug") \(point.day)")
                )
                .foregroundStyle(by: .value("Service", point.service.name))
            }
            .chartForegroundStyleScale(colorScale)
            .chartYScale(domain: labels)
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: CGFloat(days.count) * 22 + 20)
            Text("Horizontal — \(days.count) days (≤ 14).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func verticalChart(days: [Int]) -> some View {
        let points = dataPoints(for: days)
        return VStack(alignment: .leading, spacing: 4) {
            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.day),
                    y: .value("Minutes", point.minutes)
                )
                .foregroundStyle(by: .value("Service", point.service.name))
            }
            .chartForegroundStyleScale(colorScale)
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 170)
            Text("Vertical — \(days.count) days (> 14). One column per day.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

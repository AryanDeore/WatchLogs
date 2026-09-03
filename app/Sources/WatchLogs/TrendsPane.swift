import Charts
import Foundation
import SwiftUI
import WatchLogsKit

/// Swift Charts was tried at both densities and pulled back out for the
/// ≤14-Day case: at popover width the categorical y-axis labels overlapped
/// the bars, the plot border added clutter a 380pt panel can't afford, and a
/// "minutes" x-axis reads worse than just printing "3h 32m" at the end of
/// each row. The >14-Day case keeps Swift Charts because individual rows
/// stop being readable anyway and its axis thinning is worth having.
struct TrendsPane: View {
    let data: MenubarPopoverData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if data.trends.isEmpty {
                Text("Nothing watched yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if data.trends.count == 1 {
                singleDayMix(day: data.trends[0])
            } else if data.trends.count <= 14 {
                horizontalBars(days: data.trends)
            } else {
                verticalChart(days: data.trends)
            }

            if !presentBuckets.isEmpty {
                legend
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Only the services that actually have watched time somewhere in the
    /// resolved range — a legend swatch for a service with no bar is noise.
    private var presentBuckets: [ServiceDisplayBucket] {
        ServiceDisplayBucket.allCases.filter { bucket in
            data.trends.contains { ($0.totals[bucket]?.watchedMs ?? 0) > 0 }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(presentBuckets, id: \.self) { bucket in
                HStack(spacing: 4) {
                    Circle().fill(bucketColor(bucket)).frame(width: 7, height: 7)
                    Text(bucket.name).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func singleDayMix(day: DaySeriesEntry) -> some View {
        let entries = ServiceDisplayBucket.allCases.compactMap { bucket -> (ServiceDisplayBucket, Int)? in
            let watched = day.totals[bucket]?.watchedMs ?? 0
            return watched > 0 ? (bucket, watched) : nil
        }
        return Group {
            if entries.isEmpty {
                Text("Nothing watched yet").font(.caption).foregroundStyle(.tertiary)
            } else {
                let maxMs = entries.map(\.1).max() ?? 1
                VStack(spacing: 9) {
                    ForEach(entries, id: \.0) { bucket, watched in
                        TrendRow(
                            label: bucket.name,
                            totalMs: watched,
                            segments: [(bucket, watched)],
                            scaleMax: maxMs,
                            barHeight: BarMetrics.pane
                        )
                    }
                }
            }
        }
    }

    private func horizontalBars(days: [DaySeriesEntry]) -> some View {
        let maxDay = max(days.map(\.totalMs).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 9) {
                ForEach(days) { day in
                    let segments = ServiceDisplayBucket.allCases.compactMap { bucket -> (ServiceDisplayBucket, Int)? in
                        let watched = day.totals[bucket]?.watchedMs ?? 0
                        return watched > 0 ? (bucket, watched) : nil
                    }
                    TrendRow(
                        label: shortDayLabel(day.label),
                        totalMs: day.totalMs,
                        segments: segments,
                        scaleMax: maxDay,
                        barHeight: BarMetrics.pane
                    )
                }
            }
        }
    }

    private func verticalChart(days: [DaySeriesEntry]) -> some View {
        struct DataPoint: Identifiable {
            let id = UUID()
            let day: Date
            let bucket: ServiceDisplayBucket
            let watchedMs: Int
        }
        let points: [DataPoint] = days.flatMap { day -> [DataPoint] in
            guard let date = parseIsoDay(day.label) else { return [] }
            return ServiceDisplayBucket.allCases.compactMap { bucket -> DataPoint? in
                let watched = day.totals[bucket]?.watchedMs ?? 0
                return watched > 0 ? DataPoint(day: date, bucket: bucket, watchedMs: watched) : nil
            }
        }
        let colorScale: KeyValuePairs<String, Color> = [
            ServiceDisplayBucket.youtube.name: bucketColor(.youtube),
            ServiceDisplayBucket.netflix.name: bucketColor(.netflix),
            ServiceDisplayBucket.otherSites.name: bucketColor(.otherSites),
        ]
        return VStack(alignment: .leading, spacing: 4) {
            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.day),
                    y: .value("Minutes", Double(point.watchedMs) / 60_000)
                )
                .foregroundStyle(by: .value("Service", point.bucket.name))
            }
            .chartForegroundStyleScale(colorScale)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text("\(Int((minutes / 60).rounded()))h").font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
    }
}

/// Fixed label column, full-width stacked track, value column. The track is
/// the same width every row, so days are comparable at a glance and an empty
/// day reads as an empty track rather than a missing row.
private struct TrendRow: View {
    let label: String
    let totalMs: Int
    let segments: [(ServiceDisplayBucket, Int)]
    let scaleMax: Int
    let barHeight: CGFloat

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
                        ForEach(segments, id: \.0) { bucket, ms in
                            Rectangle()
                                .fill(bucketColor(bucket))
                                .frame(width: geo.size.width * (Double(ms) / Double(max(scaleMax, 1))))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: barHeight)

            Text(totalMs > 0 ? formatWatchedTime(milliseconds: totalMs) : "—")
                .font(.caption)
                .foregroundStyle(totalMs > 0 ? .secondary : .tertiary)
                .monospacedDigit()
                .frame(width: 52, alignment: .leading)
        }
    }
}

private let isoDayParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private func parseIsoDay(_ label: String) -> Date? {
    isoDayParser.date(from: label)
}

private func shortDayLabel(_ label: String) -> String {
    guard let date = parseIsoDay(label) else { return label }
    let weekday = date.formatted(.dateTime.weekday(.abbreviated))
    let day = date.formatted(.dateTime.day())
    return "\(weekday) \(day)"
}

import Foundation
import SwiftUI
import WatchLogsKit

struct HistoryPane: View {
    let data: MenubarPopoverData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if data.history.isEmpty {
                Text("Nothing watched yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(14)
            } else if data.range == .today, let today = data.history.first {
                // Today would only restate the range chip, so videos are listed
                // flat instead of nested under a day header.
                VideoList(videos: today.videos, barHeight: BarMetrics.history)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                ForEach(data.history) { day in
                    HistoryDayRow(day: day, barHeight: BarMetrics.history)
                    Divider().padding(.horizontal, 14)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Hand-rolled instead of DisclosureGroup so the whole header row toggles, not
/// only the triangle.
private struct HistoryDayRow: View {
    let day: HistoryDay
    let barHeight: CGFloat
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(dayWeekdayName(day.label))
                                .font(.callout.weight(.semibold))
                            Text(dayShortDate(day.label))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(activitySpan(day))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)

                    Text(formatWatchedTime(milliseconds: day.watchedMs))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VideoList(videos: day.videos, barHeight: barHeight)
                    .padding(.top, 8)
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// First activity → last activity. An activity-flexed Day (ADR 0001) can
    /// run past midnight, so the end time carries its date when it lands on a
    /// later calendar day — otherwise a 4:20 AM → 4:00 AM span reads backwards.
    private func activitySpan(_ day: HistoryDay) -> String {
        let start = clockTime(day.firstAt)
        guard !day.isOpen else { return "\(start) → now" }
        let end = clockTime(day.lastAt)
        if Calendar.current.isDate(day.firstAt, inSameDayAs: day.lastAt) {
            return "\(start) → \(end)"
        }
        return "\(start) → \(end) \(day.lastAt.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

private struct VideoList: View {
    let videos: [HistoryVideo]
    let barHeight: CGFloat

    var body: some View {
        // 13.2pt rather than 10pt: the thin bar frees up less row height than
        // the stock ProgressView did, so tighter spacing packs rows on top of
        // each other. Held constant across bar heights, since a 2pt vs 3pt
        // swing per row would otherwise read as drift.
        VStack(alignment: .leading, spacing: 13.2) {
            ForEach(videos) { video in
                VideoRow(video: video, barHeight: barHeight)
            }
        }
    }
}

private struct VideoRow: View {
    let video: HistoryVideo
    let barHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                RowIcon(video: video)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(video.title ?? "Untitled video")
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 5) {
                        if let author = video.author {
                            Text(author)
                            Text("·")
                        }
                        Text(clockTime(video.lastWatchedAt))
                        // Shorts and Videos are told apart by the row icon; only
                        // "live" still earns a text badge.
                        if video.contentFormat == "live" {
                            Text(video.contentFormat)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(bucketColor(video.service).opacity(0.15))
                                .foregroundStyle(bucketColor(video.service))
                                .clipShape(Capsule())
                        }
                        if video.embedded {
                            Text("embedded")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(Color.orange)
                                .clipShape(Capsule())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(formatWatchedTime(milliseconds: video.watchedMs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let coverage = video.coverage {
                DurationBar(fraction: coverage, height: barHeight)
                    .padding(.leading, 22)
                    .padding(.top, 2.4)
            } else {
                Text(video.isPlaying ? "Playing now" : video.isOpen ? "Still watching" : "No fixed length")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 22)
            }
        }
    }
}

/// A YouTube row is marked by its content format — a Video, Shorts or Live
/// glyph — so a Short reads differently from a full video at a glance. Every
/// other service keeps its brand mark.
private struct RowIcon: View {
    let video: HistoryVideo

    var body: some View {
        if video.service == .youtube, let format = ContentFormat(label: video.contentFormat) {
            FormatLogo(format: format, size: 14)
        } else {
            ServiceLogo(service: video.service, size: 14)
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

private func dayWeekdayName(_ label: String) -> String {
    guard let date = parseIsoDay(label) else { return label }
    return date.formatted(.dateTime.weekday(.wide))
}

private func dayShortDate(_ label: String) -> String {
    guard let date = parseIsoDay(label) else { return label }
    return date.formatted(.dateTime.month(.abbreviated).day())
}

/// 12-hour clock time — "9:28 PM", not "21:28", so the row's timestamp never
/// reads as a duration sitting next to the watched-time figure.
private let clockTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "h:mm a"
    return formatter
}()

private func clockTime(_ date: Date) -> String {
    clockTimeFormatter.string(from: date)
}

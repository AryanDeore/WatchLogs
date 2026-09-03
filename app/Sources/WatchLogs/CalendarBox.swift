import SwiftUI
import WatchLogsKit

/// A hand-drawn calendar instead of DatePicker: DatePicker only selects one
/// date and can't render a range span as one connected highlight, which the
/// week-row / month-grid pair needs.
struct CalendarBox: View {
    let model: MenubarPopoverReadModel
    let data: MenubarPopoverData
    @State private var displayedMonth: Date = Date()
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if model.calendarExpanded {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                    Text(monthLabel)
                        .font(.subheadline.weight(.medium))
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                } else {
                    Text(data.rangeLabel)
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                Button {
                    model.calendarExpanded.toggle()
                } label: {
                    Image(systemName: model.calendarExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(model.calendarExpanded ? "Collapse" : "Expand")
            }
            .foregroundStyle(.secondary)

            if model.calendarExpanded {
                monthGrid
            } else {
                weekRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear { displayedMonth = data.activityDay }
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private var weekRow: some View {
        let activity = data.activityDay
        let weekday = calendar.component(.weekday, from: activity)
        let mondayOffset = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -mondayOffset, to: calendar.startOfDay(for: activity))!
        return HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start)!
                VStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    // Today is bold rather than circled: the in-range box behind
                    // it already marks the cell, and two shapes on the same day
                    // read as two different things.
                    Text(day.formatted(.dateTime.day()))
                        .font(isActivityToday(day) ? .callout.weight(.bold) : .callout)
                        .frame(width: 22, height: 22)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(inSelectedRange(day) ? Color.accentColor.opacity(0.12) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var monthGrid: some View {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let blanks = (calendar.component(.weekday, from: first) + 5) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: first)!.count
        let dows = ["M", "T", "W", "T", "F", "S", "S"]
        let cells: [MonthCell] = (0..<blanks).map { MonthCell(id: "blank-\($0)", day: nil, date: nil) }
            + (0..<dayCount).map { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: first)!
                return MonthCell(id: "day-\(offset)", day: offset + 1, date: date)
            }

        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(dows.indices, id: \.self) { i in
                    Text(dows[i])
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(cells) { cell in
                    if let date = cell.date, let day = cell.day {
                        let isToday = isActivityToday(date)
                        let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: data.activityDay)
                        Text("\(day)")
                            .font(isToday ? .callout.weight(.bold) : .callout)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background(inSelectedRange(date) ? Color.accentColor.opacity(0.18) : .clear)
                            .foregroundStyle(isFuture ? Color(nsColor: .tertiaryLabelColor) : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isFuture { model.selectCustomDay(date) }
                            }
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
            }
        }
    }

    private func isActivityToday(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: data.activityDay)
    }

    /// Which cells sit inside the currently resolved range.
    private func inSelectedRange(_ day: Date) -> Bool {
        let activity = calendar.startOfDay(for: data.activityDay)
        let target = calendar.startOfDay(for: day)
        switch model.range {
        case .today:
            return target == activity
        case .thisWeek:
            let mondayOffset = (calendar.component(.weekday, from: activity) + 5) % 7
            let lower = calendar.date(byAdding: .day, value: -mondayOffset, to: activity)!
            return target >= lower && target <= activity
        case .thisMonth:
            let lower = calendar.date(from: calendar.dateComponents([.year, .month], from: activity))!
            return target >= lower && target <= activity
        case let .custom(from, through):
            let lower = calendar.startOfDay(for: min(from, through))
            let upper = calendar.startOfDay(for: max(from, through))
            return target >= lower && target <= upper
        }
    }

    private struct MonthCell: Identifiable {
        let id: String
        let day: Int?
        let date: Date?
    }
}

import SwiftUI

// Kept as a custom grid rather than a native DatePicker: DatePicker
// selects a single date and can't render a range span as one connected
// highlight, which the collapsed-week-row / month-grid range picker needs.
// Everything else (fonts, colors, the "today" marker) uses system styles
// instead of the hand-rolled palette from v1.
struct CalendarBox: View {
    @Bindable var store: PopoverStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if store.calOpen {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                    Text(monthLabel).font(.subheadline.weight(.medium))
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                } else {
                    Text(MockData.rangeResolvedLabel(store.resolvedRange))
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                Button {
                    store.calOpen.toggle()
                } label: {
                    Image(systemName: store.calOpen ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(store.calOpen ? "Collapse" : "Expand")
            }
            .foregroundStyle(.secondary)

            if store.calOpen {
                monthGrid
            } else {
                weekRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        var comps = DateComponents()
        comps.year = store.calYear
        comps.month = store.calMonth
        comps.day = 1
        let date = Calendar.current.date(from: comps) ?? Date()
        return formatter.string(from: date)
    }

    private func shiftMonth(_ delta: Int) {
        store.calMonth += delta
        if store.calMonth < 1 { store.calMonth = 12; store.calYear -= 1 }
        if store.calMonth > 12 { store.calMonth = 1; store.calYear += 1 }
    }

    private var weekRow: some View {
        let days = Array(25...31)
        let range = store.resolvedRange
        return HStack(spacing: 2) {
            ForEach(days, id: \.self) { day in
                let inRange = range.map { $0.contains(day) } ?? false
                VStack(spacing: 3) {
                    Text(MockData.weekdayLetter[day] ?? "")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    // Today is bold rather than circled: the in-range box
                    // behind it already marks the cell, and two shapes on the
                    // same day read as two different things.
                    Text("\(day)")
                        .font(day == MockData.today ? .callout.weight(.bold) : .callout)
                        .frame(width: 22, height: 22)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(inRange ? Color.accentColor.opacity(0.12) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var monthGrid: some View {
        let isAugust2026 = store.calMonth == 8 && store.calYear == 2026
        let dim = daysInMonth
        let lead = leadingBlankCount
        let range = store.resolvedRange
        let dows = ["M", "T", "W", "T", "F", "S", "S"]

        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(dows.indices, id: \.self) { i in
                    Text(dows[i]).font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            // One flat array of cells, each with its own id. Two sibling
            // ForEachs — 0..<lead for the blanks and 1...dim for the days —
            // collided on ids 1…lead, and the grid silently dropped the days
            // that lost, which is why the first few of each month vanished.
            let cells: [MonthCell] = (0..<lead).map { MonthCell(id: "blank-\($0)", day: nil) }
                + (1...dim).map { MonthCell(id: "day-\($0)", day: $0) }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(cells) { cell in
                    if let day = cell.day {
                        let inRange = isAugust2026 && (range.map { $0.contains(day) } ?? false)
                        let isToday = isAugust2026 && day == MockData.today
                        let isFuture = isAugust2026 && day > MockData.today
                        Text("\(day)")
                            .font(isToday ? .callout.weight(.bold) : .callout)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background(inRange ? Color.accentColor.opacity(0.18) : Color.clear)
                            .foregroundStyle(isFuture ? Color(nsColor: .tertiaryLabelColor) : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture { if isAugust2026 { store.pickCustomDay(day) } }
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
            }
        }
    }

    private struct MonthCell: Identifiable {
        let id: String
        let day: Int? // nil = leading blank before the 1st
    }

    private var daysInMonth: Int {
        var comps = DateComponents(); comps.year = store.calYear; comps.month = store.calMonth
        let date = Calendar.current.date(from: comps) ?? Date()
        return Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    private var leadingBlankCount: Int {
        var comps = DateComponents(); comps.year = store.calYear; comps.month = store.calMonth; comps.day = 1
        let date = Calendar.current.date(from: comps) ?? Date()
        let weekday = Calendar.current.component(.weekday, from: date)
        return (weekday + 5) % 7
    }
}

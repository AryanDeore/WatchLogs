import SwiftUI

struct CalendarBox: View {
    @Bindable var store: PopoverStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if store.calOpen {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    Text(monthLabel)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                } else {
                    Text(MockData.rangeResolvedLabel(store.resolvedRange))
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                }
                Spacer()
                Button(store.calOpen ? "collapse ▴" : "expand ▾") {
                    store.calOpen.toggle()
                }
                .buttonStyle(.bordered)
                .font(.system(size: 10))
            }

            if store.calOpen {
                monthGrid
            } else {
                weekRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .overlay(Divider(), alignment: .bottom)
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
        return HStack(spacing: 1) {
            ForEach(days, id: \.self) { day in
                let inRange = range.map { $0.contains(day) } ?? false
                VStack(spacing: 2) {
                    Text(MockData.weekdayLetter[day] ?? "")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    Text("\(day)")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 18, height: 16)
                        .background(day == MockData.today ? Color.accentColor : .clear)
                        .foregroundStyle(day == MockData.today ? .white : .primary)
                        .clipShape(Circle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(inRange ? Color.accentColor.opacity(0.14) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { store.pickCustomDay(day) }
            }
        }
    }

    private var monthGrid: some View {
        let isAugust2026 = store.calMonth == 8 && store.calYear == 2026
        let dim = daysInMonth
        let lead = leadingBlankCount
        let range = store.resolvedRange
        let dows = ["M", "T", "W", "T", "F", "S", "S"]

        return VStack(spacing: 1) {
            HStack(spacing: 1) {
                ForEach(dows.indices, id: \.self) { i in
                    Text(dows[i]).font(.system(size: 8.5)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 24) }
                ForEach(1...dim, id: \.self) { day in
                    let inRange = isAugust2026 && (range.map { $0.contains(day) } ?? false)
                    let isToday = isAugust2026 && day == MockData.today
                    let isFuture = isAugust2026 && day > MockData.today
                    Text("\(day)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isFuture ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(isToday ? Color.accentColor : (inRange ? Color.accentColor.opacity(0.14) : Color.clear))
                        .foregroundStyle(isToday ? Color.white : (isFuture ? Color(nsColor: .tertiaryLabelColor) : Color.primary))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { if isAugust2026 { store.pickCustomDay(day) } }
                }
            }
        }
    }

    private var daysInMonth: Int {
        var comps = DateComponents(); comps.year = store.calYear; comps.month = store.calMonth
        let date = Calendar.current.date(from: comps) ?? Date()
        return Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    private var leadingBlankCount: Int {
        var comps = DateComponents(); comps.year = store.calYear; comps.month = store.calMonth; comps.day = 1
        let date = Calendar.current.date(from: comps) ?? Date()
        let weekday = Calendar.current.component(.weekday, from: date) // 1 = Sunday ... 7 = Saturday
        return (weekday + 5) % 7 // Monday-first offset
    }
}

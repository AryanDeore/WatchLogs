import SwiftUI

struct CalendarBox: View {
    @Bindable var store: PopoverStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if store.calOpen {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkDim).font(.system(size: 13))
                    Text(monthLabel)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkDim).font(.system(size: 13))
                } else {
                    Text(MockData.rangeResolvedLabel(store.resolvedRange))
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                Button(store.calOpen ? "collapse ▴" : "expand ▾") {
                    store.calOpen.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkDim)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line2, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.inkDim)

            if store.calOpen {
                monthGrid
            } else {
                weekRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
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
                let isStart = inRange && day == range?.lowerBound
                let isEnd = inRange && day == range?.upperBound
                VStack(spacing: 2) {
                    Text(MockData.weekdayLetter[day] ?? "")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Theme.inkFaint)
                        .textCase(.uppercase)
                    Text("\(day)")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 18, height: 16)
                        .background(day == MockData.today ? Theme.accent : .clear)
                        .foregroundStyle(day == MockData.today ? .white : Theme.ink)
                        .clipShape(Circle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(inRange ? Theme.accentSoft : .clear)
                .clipShape(rangeShape(isStart: isStart, isEnd: isEnd, active: inRange))
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
                    Text(dows[i]).font(.system(size: 8.5)).foregroundStyle(Theme.inkFaint)
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
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(isToday ? Theme.accent : (inRange ? Theme.accentSoft : Color.clear))
                        .foregroundStyle(isToday ? Color.white : (isFuture ? Theme.inkFaint : Theme.ink))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { if isAugust2026 { store.pickCustomDay(day) } }
                }
            }
        }
    }

    private func rangeShape(isStart: Bool, isEnd: Bool, active: Bool) -> UnevenRoundedRectangle {
        guard active else {
            return UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 6)
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: isStart ? 6 : 0,
            bottomLeadingRadius: isStart ? 6 : 0,
            bottomTrailingRadius: isEnd ? 6 : 0,
            topTrailingRadius: isEnd ? 6 : 0
        )
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

import Observation

@Observable
final class PopoverStore {
    var range: RangePreset = .week
    var pane: Pane = .history
    var calOpen = false // false = collapsed week row, true = full month grid
    var calMonth = 8 // 1-12; mock data spans Jun–Aug 2026
    var calYear = 2026
    var customStart: MockDate?
    var customEnd: MockDate?
    var youtubeExpanded = true
    var settingsOpen = false
    var settings = MockSettings()

    var resolvedRange: ClosedRange<MockDate>? {
        MockData.rangeDays(range, customStart: customStart, customEnd: customEnd)
    }

    var grandTotal: Int {
        guard let resolvedRange else { return 0 }
        return MockData.grandTotal(over: resolvedRange)
    }

    func pick(_ preset: RangePreset) {
        range = preset
        // Calendar stays collapsed for every preset — the resolved-range label
        // carries the orientation. Only Custom needs the full grid to pick
        // arbitrary days.
        calOpen = (preset == .custom)
        if preset != .custom { customStart = nil; customEnd = nil }
    }

    func pickCustomDay(_ day: MockDate) {
        if customStart == nil || (customStart != nil && customEnd != nil) {
            customStart = day
            customEnd = nil
        } else if day < customStart! {
            customEnd = customStart
            customStart = day
        } else {
            customEnd = day
        }
        range = .custom
        calOpen = true
    }
}

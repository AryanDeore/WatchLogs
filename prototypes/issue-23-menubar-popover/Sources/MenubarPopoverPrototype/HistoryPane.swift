import SwiftUI

struct HistoryPane: View {
    @Bindable var store: PopoverStore

    private var days: [MockHistoryDay] {
        guard let range = store.resolvedRange else { return [] }
        if store.range == .today {
            return MockData.history.filter { $0.id == "today" }
        }
        return MockData.history.filter { range.contains($0.date) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // On Today the day header would only restate the range picker, so
            // the views are listed flat with nothing to expand.
            if store.range == .today {
                if let day = days.first {
                    ViewList(views: day.views, barHeight: BarMetrics.history)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
            } else {
                ForEach(days) { day in
                    HistoryDayRow(
                        day: day,
                        defaultExpanded: day.id != "d-mon",
                        barHeight: BarMetrics.history
                    )
                    Divider().padding(.horizontal, 14)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Hand-rolled instead of DisclosureGroup: DisclosureGroup only hit-tests its
// triangle, and the whole header row — day name through duration — should
// toggle.
private struct HistoryDayRow: View {
    let day: MockHistoryDay
    let barHeight: CGFloat
    @State private var isExpanded: Bool

    init(day: MockHistoryDay, defaultExpanded: Bool, barHeight: CGFloat) {
        self.day = day
        self.barHeight = barHeight
        self._isExpanded = State(initialValue: defaultExpanded)
    }

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
                            Text(day.name).font(.callout.weight(.semibold))
                            if let dateLabel = day.dateLabel {
                                Text(dateLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(day.span).font(.caption2).foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)

                    Text(MockData.formatMinutes(MockData.dayTotal(day.date)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ViewList(views: day.views, barHeight: barHeight)
                    .padding(.top, 8)
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// Explicit .leading alignment: rows whose length is unknown (live) have no
// full-width progress track to stretch them, so a default-centered VStack
// indented them past the rows that did have one.
private struct ViewList: View {
    let views: [MockView]
    let barHeight: CGFloat

    var body: some View {
        // 13.2pt rather than the original 10pt: the thin bar below frees up
        // less row height than the old ProgressView did, and without this
        // the rows just sit tighter together — see prototype v6's variant E.
        // Held constant across bar heights, since 2pt vs 3pt is a 1pt swing
        // per row and re-tuning the gap alongside it would read as drift.
        VStack(alignment: .leading, spacing: 13.2) {
            ForEach(views) { view in
                ViewRow(view: view, barHeight: barHeight)
            }
        }
    }
}

private struct ViewRow: View {
    let view: MockView
    let barHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                ServiceLogo(service: view.service, size: 14)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(view.title)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 5) {
                        Text(view.author)
                        Text("·")
                        Text(view.at)
                        if view.format != "standard" {
                            Text(view.format)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(view.format == "live" ? view.service.color.opacity(0.15) : Color.secondary.opacity(0.12))
                                .foregroundStyle(view.format == "live" ? view.service.color : .secondary)
                                .clipShape(Capsule())
                        }
                        if view.embedded {
                            Text("embedded")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(view.watched)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let coverage = view.coverage {
                DurationBar(fraction: coverage, height: barHeight)
                    .padding(.leading, 22)
                    .padding(.top, 2.4) // see ViewList's spacing comment — keeps row rhythm from the old ProgressView
            } else {
                Text("Live · no fixed length")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 22)
            }
        }
    }
}

// DurationBar and RangePreset.barHeight live in DurationBar.swift — the
// By Service and Trends panes draw the same bar at the same height.

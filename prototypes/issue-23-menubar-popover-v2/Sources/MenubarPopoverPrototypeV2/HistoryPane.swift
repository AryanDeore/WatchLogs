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
                    ViewList(views: day.views)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
            } else {
                ForEach(days) { day in
                    HistoryDayRow(day: day, defaultExpanded: day.id != "d-mon")
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
    @State private var isExpanded: Bool

    init(day: MockHistoryDay, defaultExpanded: Bool) {
        self.day = day
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
                ViewList(views: day.views)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(views) { view in
                ViewRow(view: view)
            }
        }
    }
}

private struct ViewRow: View {
    let view: MockView

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
                ProgressView(value: coverage)
                    .tint(.accentColor)
                    .padding(.leading, 22)
            } else {
                Text("Live · no fixed length")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 22)
            }
        }
    }
}

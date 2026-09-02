import SwiftUI

struct HistoryPane: View {
    @Bindable var store: PopoverStore

    private var days: [MockHistoryDay] {
        guard let range = store.resolvedRange else { return [] }
        if store.range == .today {
            return MockData.history.filter { $0.id == "today" }
        }
        return MockData.history.filter { range.contains($0.dayOfMonth) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bar under each video = how much of it you've watched.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 4)

            ForEach(days) { day in
                HistoryDayRow(day: day, defaultExpanded: day.id != "d-mon")
                Divider().padding(.leading, 14)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HistoryDayRow: View {
    let day: MockHistoryDay
    @State private var isExpanded: Bool

    init(day: MockHistoryDay, defaultExpanded: Bool) {
        self.day = day
        self._isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 10) {
                ForEach(day.views) { view in
                    ViewRow(view: view)
                }
            }
            .padding(.top, 6)
            .padding(.leading, 4)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(day.name).font(.callout.weight(.semibold))
                        if let date = day.date {
                            Text(date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(day.span).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(MockData.formatMinutes(MockData.dayTotal(day.dayOfMonth)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

private struct ViewRow: View {
    let view: MockView

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: view.service.symbol)
                    .font(.caption)
                    .foregroundStyle(view.service.color)
                    .frame(width: 14)
                    .padding(.top, 2)

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

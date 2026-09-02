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
        LazyVStack(alignment: .leading, spacing: 0) {
            Text("Bar under each video = how much of it you've watched.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(days) { day in
                dayGroup(day)
            }
        }
    }

    @ViewBuilder
    private func dayGroup(_ day: MockHistoryDay) -> some View {
        let collapsed = store.collapsedDays.contains(day.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                store.toggleDay(day.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(day.name).fontWeight(.semibold)
                            if let date = day.date {
                                Text(date).foregroundStyle(.tertiary).font(.system(size: 11.5))
                            }
                        }
                        Text(day.span)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(MockData.formatMinutes(MockData.dayTotal(day.dayOfMonth)))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                VStack(spacing: 0) {
                    ForEach(day.views) { view in
                        viewRow(view)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .overlay(Divider(), alignment: .bottom)
    }

    private func viewRow(_ view: MockView) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(view.service.color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 1) {
                    Text(view.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 6) {
                        Text(view.author)
                        Text("·")
                        Text(view.at)
                        if view.format != "standard" {
                            tag(view.format, color: view.format == "live" ? view.service.color : .blue)
                        }
                        if view.embedded {
                            tag("embedded", color: .orange)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Text(view.watched)
                    .font(.system(size: 11.5, design: .monospaced))
            }

            if let coverage = view.coverage {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(nsColor: .separatorColor))
                        Capsule().fill(Color.accentColor.opacity(0.55))
                            .frame(width: geo.size.width * coverage)
                    }
                }
                .frame(height: 3)
                .padding(.leading, 17)
            } else {
                Text("live · no fixed length")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 17)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

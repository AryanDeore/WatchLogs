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
                .foregroundStyle(Theme.inkFaint)
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
                        .foregroundStyle(Theme.inkFaint)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(day.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                            if let date = day.date {
                                Text(date).foregroundStyle(Theme.inkFaint).font(.system(size: 11.5))
                            }
                        }
                        Text(day.span)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                    Text(MockData.formatMinutes(MockData.dayTotal(day.dayOfMonth)))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
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
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 6) {
                        Text(view.author)
                        Text("·")
                        Text(view.at)
                        if view.format != "standard" {
                            tag(view.format, bg: view.format == "live" ? Theme.liveTagBg : Theme.fmtTagBg, fg: view.format == "live" ? view.service.color : Theme.fmtTagFg)
                        }
                        if view.embedded {
                            tag("embedded", bg: Theme.warnSoft, fg: Theme.warn)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkDim)
                }

                Text(view.watched)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }

            if let coverage = view.coverage {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.panel2)
                        Capsule().fill(Theme.accent.opacity(0.55))
                            .frame(width: geo.size.width * coverage)
                    }
                }
                .frame(height: 3)
                .padding(.leading, 17)
            } else {
                Text("live · no fixed length")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.leading, 17)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func tag(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

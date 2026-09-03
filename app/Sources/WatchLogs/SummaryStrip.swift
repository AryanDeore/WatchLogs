import SwiftUI
import WatchLogsKit

struct SummaryStrip: View {
    let model: MenubarPopoverReadModel
    let data: MenubarPopoverData
    @State private var hovering = false

    var body: some View {
        Button {
            model.pane = .byService
        } label: {
            HStack(spacing: 16) {
                if data.summary.isEmpty {
                    Text("No watch time in range")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(data.summary) { entry in
                        HStack(spacing: 5) {
                            ServiceLogo(service: entry.service, size: 14)
                            Text(formatWatchedTime(milliseconds: entry.totals.watchedMs))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(hovering ? Color.primary.opacity(0.06) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 6)
    }
}

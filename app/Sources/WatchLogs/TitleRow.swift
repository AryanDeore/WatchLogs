import SwiftUI
import WatchLogsKit

struct TitleRow: View {
    let model: MenubarPopoverReadModel
    let data: MenubarPopoverData

    var body: some View {
        HStack(spacing: 8) {
            Text("WatchLogs")
                .font(.headline)
            Spacer()
            Text(formatWatchedTime(milliseconds: data.total.watchedMs))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button {
                model.settingsOpen = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

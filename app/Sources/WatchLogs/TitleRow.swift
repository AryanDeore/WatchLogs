import SwiftUI
import WatchLogsKit

struct TitleRow: View {
    let model: MenubarPopoverReadModel
    let data: MenubarPopoverData
    let transport: LoopbackTransport
    
    @State private var refreshing: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text("WatchLogs")
                .font(.headline)
            Text(formatWatchedTime(milliseconds: data.total.watchedMs))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                performRefresh()
            } label: {
                if refreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh: Ask extensions to flush buffered views now")
            .disabled(refreshing)
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
    
    private func performRefresh() {
        refreshing = true
        // TODO: Implement actual flush-now mechanism via transport
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshing = false
        }
    }
}

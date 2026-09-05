import SwiftUI
import WatchLogsKit

struct TitleRow: View {
    let model: MenubarPopoverReadModel
    let data: MenubarPopoverData
    let transport: LoopbackTransport

    @State private var refreshPhase: RefreshPhase = .idle
    @State private var refreshTask: Task<Void, Never>?

    /// The App has no push channel to the Extension (issue #35 §3), so a
    /// refresh rides an "Ack-carried hint" — this is purely local UI state
    /// tracking whether that round trip has landed yet, not the request itself.
    private enum RefreshPhase: Equatable {
        case idle
        case inFlight
        case confirmed
    }

    /// A Flush has landed at least once — the button has an Extension to ask.
    private var isPaired: Bool { data.lastFlushAt != nil }

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
                switch refreshPhase {
                case .idle:
                    Image(systemName: "arrow.clockwise")
                case .inFlight:
                    ProgressView()
                        .controlSize(.small)
                case .confirmed:
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.borderless)
            .help(refreshHelp)
            .disabled(!isPaired || refreshPhase == .inFlight)
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
        .onDisappear { refreshTask?.cancel() }
    }

    private var refreshHelp: String {
        isPaired
            ? "Refresh: ask extensions to flush buffered views now"
            : "Refresh: no extension paired yet — copy the pairing string into the extension"
    }

    /// Arms the hint via `FlushCatchUp` and reflects what it finds: a
    /// checkmark if a newer Flush landed, back to idle either way after.
    private func performRefresh() {
        guard refreshPhase != .inFlight else { return }
        refreshPhase = .inFlight

        refreshTask?.cancel()
        refreshTask = FlushCatchUp.request(transport: transport) { caughtUp in
            guard caughtUp else {
                refreshPhase = .idle
                return
            }
            refreshPhase = .confirmed
            // The store has new data now, but `model` isn't watching it —
            // nothing about a Flush landing touches a tracked property on
            // its own. Without this, the checkmark shows "up to date" while
            // History/Services/Trends keep showing whatever they last
            // rendered, until the popover's own 5s timer or a pane switch
            // happens to force a re-render.
            model.markDataChanged()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1_200))
                if refreshPhase == .confirmed { refreshPhase = .idle }
            }
        }
        // Nothing paired to ask — `request` armed nothing and will never
        // call back, so this button has to reset itself.
        if refreshTask == nil { refreshPhase = .idle }
    }
}

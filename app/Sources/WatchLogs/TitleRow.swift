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

    /// How long to keep polling for the Extension's re-flush before giving up.
    /// A throttled tab can take up to its 30s sweep to notice the hint, but a
    /// button that stayed disabled that long would read as broken — 5s covers
    /// the common "tab still lively" case and leaves the rest to the
    /// popover's own periodic catch-up.
    private static let pollAttempts = 20
    private static let pollInterval: Duration = .milliseconds(250)

    /// Arms the hint, then polls the store directly (not `data`, which is a
    /// snapshot this view doesn't get to refresh) for a Flush newer than the
    /// one on hand.
    ///
    /// A bounded `for` loop over `Task.sleep`, not a repeating `Timer`: a
    /// `Timer` scheduled on the default run loop can go quiet while AppKit is
    /// running the popover's own event-tracking loop and never come back,
    /// which left this button stuck mid-spin, disabled, with no way to retry.
    /// `Task.sleep` runs on Swift Concurrency's own clock and the loop's
    /// iteration cap is the timeout — there is no "the timer forgot to fire"
    /// failure mode to have.
    private func performRefresh() {
        guard isPaired, refreshPhase != .inFlight, let before = data.lastFlushAt else { return }
        refreshPhase = .inFlight
        transport.requestFlushAgain()

        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            for _ in 0..<Self.pollAttempts {
                try? await Task.sleep(for: Self.pollInterval)
                if Task.isCancelled { return }

                guard let landed = try? transport.store.lastFlushAt(), landed > before else { continue }
                refreshPhase = .confirmed
                // The store has new data now, but `model` isn't watching it —
                // nothing about a Flush landing touches a tracked property on
                // its own. Without this, the checkmark shows "up to date"
                // while History/Services/Trends keep showing whatever they
                // last rendered, until the popover's own 5s timer or a pane
                // switch happens to force a re-render.
                model.markDataChanged()
                try? await Task.sleep(for: .milliseconds(1_200))
                if !Task.isCancelled, refreshPhase == .confirmed { refreshPhase = .idle }
                return
            }
            if !Task.isCancelled { refreshPhase = .idle }
        }
    }
}

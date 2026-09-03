import AppKit
import SwiftUI
import WatchLogsKit

/// Native `Form` instead of a hand-rolled grid — this is the same layout
/// engine the System Settings panes use, so labels, control alignment, and
/// spacing all come for free.
struct SettingsView: View {
    let model: MenubarPopoverReadModel
    let transport: LoopbackTransport

    @State private var pairingString: String = ""
    @State private var boundPort: Int = 0
    @State private var targetHour: Int = 4
    @State private var retentionDays: Int = 90
    @State private var privateWindows: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    model.settingsOpen = false
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Text("Settings").font(.headline)
                Spacer()
            }
            .padding(12)

            Divider()

            Form {
                Section {
                    LabeledContent("Pairing string") {
                        HStack(spacing: 6) {
                            Text(pairingString)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(pairingString, forType: .string)
                            }
                            Button("Regenerate") {
                                if let regenerated = try? transport.regenerateToken() {
                                    pairingString = regenerated
                                }
                            }
                        }
                    }
                    .help("Paste into the Extension once. Host, port, token.")

                    LabeledContent("Local port", value: "\(boundPort)")
                        .help("The App listens on 127.0.0.1. Re-rolls if the port is taken.")

                    Stepper(value: $retentionDays, in: 0...365) {
                        LabeledContent("Keep raw events for", value: "\(retentionDays) days")
                    }
                    .help("Views and computed time are kept forever; only the raw log is pruned.")
                    .onChange(of: retentionDays) { _, value in
                        try? transport.setRawEventRetentionDays(value)
                    }

                    Stepper(value: $targetHour, in: 0...(DayBoundary.hardCapHour - 1)) {
                        LabeledContent("My day ends around", value: String(format: "%02d:00", targetHour))
                    }
                    .help("Watching before this hour files into the previous day.")
                    .onChange(of: targetHour) { _, value in
                        try? transport.setTargetHour(value)
                    }

                    Toggle("Capture playback in private windows", isOn: $privateWindows)
                        .onChange(of: privateWindows) { _, value in
                            try? transport.setCapturesPrivateWindows(value)
                        }
                }

                Section {
                    Button("Rebuild statistics") {
                        try? transport.rebuildStatistics()
                    }
                    Button("Quit WatchLogs") {
                        NSApp.terminate(nil)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        // No background of its own: PopoverView swaps this in for the panes,
        // so it sits directly on the popover's vibrancy material.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: reload)
    }

    private func reload() {
        pairingString = transport.pairingString()
        boundPort = transport.boundPort ?? 0
        targetHour = (try? transport.targetHour()) ?? 4
        retentionDays = (try? transport.rawEventRetentionDays()) ?? 90
        privateWindows = (try? transport.capturesPrivateWindows()) ?? false
    }
}

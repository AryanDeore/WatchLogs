import AppKit
import SwiftUI
import WatchLogsKit

/// Native `Form` instead of a hand-rolled grid — this is the same layout
/// engine the System Settings panes use, so labels, control alignment, and
/// spacing all come for free.
struct SettingsView: View {
    let model: MenubarPopoverReadModel
    let transport: LoopbackTransport
    let settings: AppSettings

    @State private var pairingString: String = ""
    @State private var boundPort: Int = 0
    @State private var targetHour: Int = 4
    @State private var retentionDays: Int = 90
    @State private var privateWindows: Bool = false
    @State private var launchAtLogin: Bool = false
    
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let version = "0.1.0"
    private let buildNumber = "1"

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
                Section("Menubar Icon") {
                        Picker("What shows", selection: Binding(
                            get: { settings.iconDisplay },
                            set: { settings.iconDisplay = $0 }
                        )) {
                            ForEach(AppSettings.IconDisplay.allCases, id: \.self) { display in
                                Text(display.label).tag(display)
                            }
                        }
                        .help("Choose what appears in the menubar.")
                        
                        if settings.iconDisplay != .iconOnly {
                            Picker("Time separator", selection: Binding(
                                get: { settings.timeSeparator },
                                set: { settings.timeSeparator = $0 }
                            )) {
                                ForEach(AppSettings.TimeSeparator.allCases, id: \.self) { separator in
                                    Text(separator.label).tag(separator)
                                }
                            }
                            .help("Format for time over one hour.")
                        }
                        
                        Toggle("Blink the icon while a video is playing", isOn: Binding(
                            get: { settings.blinkIconWhilePlaying },
                            set: { settings.blinkIconWhilePlaying = $0 }
                        ))
                        .help("The play mark pulses while actively watching.")
                        
                        if settings.iconDisplay == .iconAndTime && settings.timeSeparator == .colon {
                            Toggle("Blink the separator", isOn: Binding(
                                get: { settings.blinkSeparator },
                                set: { settings.blinkSeparator = $0 }
                            ))
                            .help("The colon blinks at 1 Hz while counting.")
                        }
                }
                
                Section("General") {
                    Toggle("Launch WatchLogs at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            try? launchAtLoginManager.setEnabled(enabled)
                        }
                    
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
                
                Section("Extension") {
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
                        }
                    }
                    .help("Paste into the Extension once. Host, port, token.")

                    LabeledContent("Local port", value: "\(boundPort)")
                        .help("The App listens on 127.0.0.1. Re-rolls if the port is taken.")
                }

                Section {
                    Button("Quit WatchLogs") {
                        NSApp.terminate(nil)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Author footer, pinned to the bottom
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Text("WatchLogs v\(version) (\(buildNumber))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Link("GitHub", destination: URL(string: "https://github.com/AryanDeore/WatchLogs")!)
                        .font(.caption)
                    
                    Link("Author", destination: URL(string: "https://github.com/AryanDeore")!)
                        .font(.caption)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
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
        launchAtLogin = launchAtLoginManager.isEnabled
    }
    

}

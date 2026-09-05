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
                    Picker("Menubar icon", selection: Binding(
                        get: { settings.iconDisplay },
                        set: { settings.iconDisplay = $0 }
                    )) {
                        Label {
                            Text("Icon only")
                        } icon: {
                            LogPlayMarkView()
                        }
                        .tag(AppSettings.IconDisplay.iconOnly)
                        
                        Label {
                            Text("Icon + time")
                        } icon: {
                            HStack(spacing: 3) {
                                LogPlayMarkView()
                                Text("1h05").font(.caption2)
                            }
                        }
                        .tag(AppSettings.IconDisplay.iconAndTime)
                        
                        Label {
                            Text("Time only")
                        } icon: {
                            Text("1h05").font(.caption2)
                        }
                        .tag(AppSettings.IconDisplay.timeOnly)
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
                    
                    if settings.iconDisplay == .iconAndTime && settings.timeSeparator == .colon {
                        Toggle("Blink separator", isOn: Binding(
                            get: { settings.blinkSeparator },
                            set: { settings.blinkSeparator = $0 }
                        ))
                        .help("The colon blinks at 1 Hz while counting.")
                    }
                }
                .padding(.bottom, -6)
                
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
                .padding(.bottom, -6)
                
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
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Spacer()
            
            // Quit button
            HStack {
                Spacer()
                Button("Quit WatchLogs") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
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

/// SwiftUI view for the LogPlayMark icon (three stepped bars)
struct LogPlayMarkView: View {
    var body: some View {
        Canvas { context, size in
            let leftInset = size.width * 0.24
            let barHeight = size.height * 0.15
            
            func bar(widthFraction: CGFloat, yFraction: CGFloat) {
                let width = size.width * widthFraction
                let y = size.height * (1 - yFraction) - barHeight / 2
                let rect = CGRect(x: leftInset, y: y, width: width, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: barHeight / 2)
                context.fill(path, with: .color(.primary))
            }
            
            bar(widthFraction: 0.26, yFraction: 0.28)
            bar(widthFraction: 0.52, yFraction: 0.50)
            bar(widthFraction: 0.26, yFraction: 0.72)
        }
        .frame(width: 14, height: 14)
    }
}

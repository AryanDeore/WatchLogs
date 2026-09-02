import SwiftUI

// Native Form instead of v1's hand-rolled .field/.set divs — this is the
// same layout engine System Settings panes use, so labels, control
// alignment, and spacing come for free.
struct SettingsView: View {
    @Bindable var store: PopoverStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    store.settingsOpen = false
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
                        HStack {
                            Text(store.settings.pairingToken).font(.system(.body, design: .monospaced))
                            Button("Copy") {}
                            Button("Regenerate") {}
                        }
                    }
                    .help("Paste into the Extension once. Host, port, token.")

                    LabeledContent("Local port") {
                        Text("\(store.settings.port)")
                    }
                    .help("App listens on 127.0.0.1. Re-rolls if taken.")

                    Stepper(value: $store.settings.retentionDays, in: 0...365) {
                        LabeledContent("Keep raw events for", value: "\(store.settings.retentionDays) days")
                    }
                    .help("Views and computed time are kept forever; only the raw log is pruned.")

                    LabeledContent("My day ends around", value: store.settings.dayEndsAround)
                        .help("Watching before this hour files into the previous day.")

                    Toggle("Launch at login", isOn: $store.settings.launchAtLogin)
                }

                Section {
                    Button("Rebuild statistics") {}
                    LabeledContent("Version", value: store.settings.version)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        // The slide-over sits on top of the popover in a ZStack, so it has
        // to be fully opaque and fill the frame — otherwise the pane behind
        // it shows through and the two sets of text overlap.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

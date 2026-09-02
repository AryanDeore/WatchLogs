import SwiftUI

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
                .buttonStyle(.plain)
                Text("Settings").fontWeight(.bold)
                Spacer()
            }
            .padding(12)
            .overlay(Divider(), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field(label: "Pairing string", hint: "Paste into the Extension once. Host, port, token.") {
                        HStack(spacing: 6) {
                            Text(store.settings.pairingToken)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Button("Copy") {}.buttonStyle(.bordered).font(.system(size: 11))
                            Button("Regenerate") {}.buttonStyle(.bordered).font(.system(size: 11))
                        }
                    }

                    field(label: "Local port", hint: "App listens on 127.0.0.1. Re-rolls if taken.") {
                        Text("\(store.settings.port)")
                            .font(.system(size: 12, design: .monospaced))
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    field(label: "Keep raw events for", hint: "Views and computed time are kept forever; only the raw log is pruned.") {
                        stepper(value: "\(store.settings.retentionDays) days") {
                            store.settings.retentionDays = max(0, store.settings.retentionDays - 1)
                        } increment: {
                            store.settings.retentionDays += 1
                        }
                    }

                    field(label: "My day ends around", hint: "Watching before this hour files into the previous day.") {
                        stepper(value: store.settings.dayEndsAround) {} increment: {}
                    }

                    field(label: "Launch at login", hint: nil) {
                        Toggle("", isOn: $store.settings.launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Text(store.settings.version)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Text("Rebuild statistics").font(.system(size: 11))
                        .foregroundStyle(.blue)
                        .onTapGesture {}
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(label: String, hint: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold))
            if let hint {
                Text(hint).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            content()
        }
    }

    private func stepper(value: String, decrement: @escaping () -> Void, increment: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button("–", action: decrement).buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 5)
            Text(value).font(.system(size: 12, design: .monospaced)).padding(.horizontal, 12)
                .overlay(Rectangle().frame(width: 1).foregroundStyle(Color(nsColor: .separatorColor)), alignment: .leading)
                .overlay(Rectangle().frame(width: 1).foregroundStyle(Color(nsColor: .separatorColor)), alignment: .trailing)
            Button("+", action: increment).buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 5)
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

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
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkDim)
                }
                .buttonStyle(.plain)
                Text("Settings").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(12)
            .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field(label: "Pairing string", hint: "Paste into the Extension once. Host, port, token.") {
                        HStack(spacing: 6) {
                            Text(store.settings.pairingToken)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line2, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            miniButton("Copy") {}
                            miniButton("Regenerate") {}
                        }
                    }

                    field(label: "Local port", hint: "App listens on 127.0.0.1. Re-rolls if taken.") {
                        Text("\(store.settings.port)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line2, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
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
                        toggleSwitch(isOn: $store.settings.launchAtLogin)
                    }

                    Text(store.settings.version)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)

                    Text("Rebuild statistics")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                        .onTapGesture {}
                }
                .padding(14)
            }
        }
        .background(Theme.card)
    }

    @ViewBuilder
    private func field<Content: View>(label: String, hint: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
            if let hint {
                Text(hint).font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
            }
            content()
        }
    }

    private func miniButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line2, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .fixedSize()
    }

    private func stepper(value: String, decrement: @escaping () -> Void, increment: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button("–", action: decrement)
                .buttonStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 5)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .overlay(Rectangle().frame(width: 1).foregroundStyle(Theme.line2), alignment: .leading)
                .overlay(Rectangle().frame(width: 1).foregroundStyle(Theme.line2), alignment: .trailing)
            Button("+", action: increment)
                .buttonStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line2, lineWidth: 1))
    }

    private func toggleSwitch(isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule().fill(isOn.wrappedValue ? Theme.good : Theme.line2)
                    .frame(width: 34, height: 20)
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
    }
}

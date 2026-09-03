import SwiftUI

struct TitleRow: View {
    @Bindable var store: PopoverStore

    var body: some View {
        HStack(spacing: 8) {
            Text("WatchLogs")
                .font(.headline)
            Spacer()
            Text("\(store.range.label) · \(MockData.formatMinutes(store.grandTotal))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                store.settingsOpen = true
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

import SwiftUI

struct TitleRow: View {
    @Bindable var store: PopoverStore

    var body: some View {
        HStack(spacing: 10) {
            (Text("Watch").fontWeight(.bold) + Text("·").foregroundStyle(.blue).fontWeight(.bold) + Text("Logs").fontWeight(.bold))
                .font(.system(size: 13))

            Spacer()

            Text("\(store.range.label) · \(MockData.formatMinutes(store.grandTotal))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Button {
                store.settingsOpen = true
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.bordered)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Divider(), alignment: .bottom)
    }
}

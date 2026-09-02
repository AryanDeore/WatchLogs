import SwiftUI

struct TitleRow: View {
    @Bindable var store: PopoverStore

    var body: some View {
        HStack(spacing: 10) {
            (Text("Watch").foregroundStyle(Theme.ink)
                + Text("·").foregroundStyle(Theme.accent)
                + Text("Logs").foregroundStyle(Theme.ink))
                .font(.system(size: 13, weight: .bold))

            Spacer()

            Text("\(store.range.label) · \(MockData.formatMinutes(store.grandTotal))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.inkDim)

            Button {
                store.settingsOpen = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkDim)
                    .frame(width: 26, height: 26)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line2, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }
}

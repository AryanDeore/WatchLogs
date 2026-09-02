import SwiftUI

struct SummaryStrip: View {
    @Bindable var store: PopoverStore

    private var top3: [(service: Service, minutes: Int)] {
        guard let range = store.resolvedRange else { return [] }
        let totals = MockData.serviceTotals(over: range)
        return totals.filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (service: $0.key, minutes: $0.value) }
    }

    var body: some View {
        Button {
            store.pane = .byService
        } label: {
            HStack(spacing: 14) {
                if top3.isEmpty {
                    Text("no watch time in range")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                } else {
                    ForEach(top3, id: \.service) { entry in
                        HStack(spacing: 5) {
                            Text(entry.service.mono)
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 15, height: 15)
                                .background(entry.service.color)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(MockData.formatMinutes(entry.minutes))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.inkDim)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.panel)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }
}

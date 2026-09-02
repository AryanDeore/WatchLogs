import SwiftUI

struct SummaryStrip: View {
    @Bindable var store: PopoverStore
    @State private var hovering = false

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
            HStack(spacing: 16) {
                if top3.isEmpty {
                    Text("No watch time in range")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(top3, id: \.service) { entry in
                        HStack(spacing: 5) {
                            ServiceLogo(service: entry.service, size: 14)
                            Text(MockData.formatMinutes(entry.minutes))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(hovering ? Color.primary.opacity(0.06) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 6)
    }
}

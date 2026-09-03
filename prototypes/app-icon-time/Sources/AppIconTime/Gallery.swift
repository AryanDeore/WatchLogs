import SwiftUI

/// Every variant at real menu-bar size on a light tile, a dark tile, and a 2x
/// zoom tile. Wrapped in one TimelineView so the whole page ticks together
/// while "simulate watching" is on.
struct GalleryView: View {
    @Bindable var model: PrototypeModel

    private let columns = [GridItem(.adaptive(minimum: 460), spacing: 16)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let now = ctx.date
            let seconds = model.watchedSeconds(at: now)
            let colonOn = Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0

            VStack(spacing: 0) {
                controls(seconds: seconds)
                Divider()
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(IconTimeVariant.allCases) { variant in
                            GalleryCell(
                                variant: variant,
                                seconds: seconds,
                                colonOn: colonOn,
                                isCounting: model.isCounting,
                                goalHours: model.goalHours,
                                isSelected: model.selectedVariant == variant,
                                onSelect: { model.selectedVariant = variant }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    @ViewBuilder
    private func controls(seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App-icon + running watched time — 10 prototypes")
                .font(.title3.weight(.semibold))

            HStack(spacing: 12) {
                Text("Watched time").frame(width: 96, alignment: .leading)
                Slider(value: $model.watchedMinutes, in: 0...300)
                    .disabled(model.isCounting)
                Text(TimeParts(seconds: seconds).compact)
                    .font(.system(.body, design: .rounded)).monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }

            HStack(spacing: 12) {
                Toggle("Simulate watching", isOn: $model.counting)
                Divider().frame(height: 16)
                Text("Jump:").foregroundStyle(.secondary)
                Button("47m") { model.setWatched(minutes: 47) }
                Button("1:05") { model.setWatched(minutes: 65) }
                Button("2:30") { model.setWatched(minutes: 150) }
                Button("9:59") { model.setWatched(minutes: 599) }
                Spacer()
            }
            .disabled(false)

            HStack(spacing: 12) {
                Text("Goal (ring)").frame(width: 96, alignment: .leading)
                Slider(value: $model.goalHours, in: 1...8)
                Text(String(format: "%.1f h", model.goalHours))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct GalleryCell: View {
    let variant: IconTimeVariant
    let seconds: Int
    let colonOn: Bool
    let isCounting: Bool
    let goalHours: Double
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(variant.title).font(.headline)
                Spacer()
                if isSelected {
                    Text("in menu bar")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(AppLogoTheme.accent.opacity(0.18)))
                        .foregroundStyle(AppLogoTheme.accent)
                } else {
                    Button("Show in menu bar", action: onSelect)
                        .buttonStyle(.link).font(.caption)
                }
            }

            Text(variant.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                tile(dark: false, zoom: 1)
                tile(dark: true, zoom: 1)
                tile(dark: false, zoom: 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? AppLogoTheme.accent : Color.gray.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1)
        )
    }

    private func tile(dark: Bool, zoom: CGFloat) -> some View {
        let w: CGFloat = zoom == 1 ? 132 : 210
        let h: CGFloat = 26 * zoom
        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(dark ? Color.black : Color.white)
                VariantLabel(
                    variant: variant,
                    seconds: seconds,
                    isCounting: isCounting,
                    colonOn: colonOn,
                    goalHours: goalHours
                )
                .environment(\.colorScheme, dark ? .dark : .light)
                .scaleEffect(zoom)
            }
            .frame(width: w, height: h)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.25)))

            Text(zoom == 1 ? (dark ? "dark" : "light") : "2×")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

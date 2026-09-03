import SwiftUI

/// The mark alone, with the current pulse sample applied. Used both magnified
/// in the lab and at 13 pt in the menu-bar composite.
struct PulsingMark: View {
    let size: CGFloat
    let sample: PulseSample

    var body: some View {
        LogPlayMark(size: size, color: sample.color ?? .primary)
            .opacity(sample.opacity)
            .scaleEffect(sample.scale)
            .frame(width: size, height: size)
    }
}

/// Variant 7 ("unit suffixed") from `prototypes/app-icon-time`, at menu-bar
/// size. Only the mark pulses; the readout is static.
struct PulseMenuLabel: View {
    let sample: PulseSample
    let timeStyle: TimeStyle

    private let barFont = Font.system(size: 13, weight: .regular, design: .rounded)
    private let unitFont = Font.system(size: 9, weight: .medium, design: .rounded)

    var body: some View {
        HStack(spacing: 4) {
            PulsingMark(size: 13, sample: sample)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                switch timeStyle {
                case .underHour:
                    Text("47").font(barFont).monospacedDigit()
                    Text("min").font(unitFont).foregroundStyle(.secondary)
                case .overHour:
                    Text("1").font(barFont).monospacedDigit()
                    Text("h").font(unitFont).foregroundStyle(.secondary)
                    Text("05").font(barFont).monospacedDigit()
                }
            }
        }
        .fixedSize()
    }
}

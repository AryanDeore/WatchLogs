import SwiftUI

/// Ten structurally different takes on "the shipped mark + a running
/// watched-time readout, living in the macOS menu bar."
enum IconTimeVariant: String, CaseIterable, Identifiable, Hashable {
    case inlineTrailing
    case timeOnly
    case reversedPill
    case stackedMicro
    case markAsSeparator
    case goalRing
    case unitSuffixed
    case lcdStopwatch
    case liveDot
    case blinkingColon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inlineTrailing:  "1 — Inline trailing"
        case .timeOnly:        "2 — Time only"
        case .reversedPill:    "3 — Reversed pill"
        case .stackedMicro:    "4 — Stacked micro"
        case .markAsSeparator: "5 — Mark as separator"
        case .goalRing:        "6 — Goal ring"
        case .unitSuffixed:    "7 — Unit suffixed"
        case .lcdStopwatch:    "8 — LCD stopwatch"
        case .liveDot:         "9 — Live dot"
        case .blinkingColon:   "10 — Blinking colon"
        }
    }

    var note: String {
        switch self {
        case .inlineTrailing:
            "The obvious one: mark at ship size, one space, monospaced-digit time. Baseline to judge the rest against."
        case .timeOnly:
            "No mark in the bar at all — just the number. The mark returns in the popover. Tests whether the glyph still earns its pixels next to a readout."
        case .reversedPill:
            "Time knocked out of a filled accent capsule, tiny mark as a prefix inside it. Reads as a status badge, not an app icon."
        case .stackedMicro:
            "Two lines inside the 22-pt bar: a 6-pt WATCHED label over the time, mark to the left. Deliberately cramped — does it survive Retina + non-Retina?"
        case .markAsSeparator:
            "The play mark literally stands in for the colon: 1 ▷ 05. Falls back to plain minutes under an hour (no separator to replace)."
        case .goalRing:
            "A progress ring around a mini mark shows fraction of a daily goal; the time trails outside. Adds a second data dimension to the same slot."
        case .unitSuffixed:
            "Explicit units instead of a colon: 47min / 1h05, unit in a lighter weight. Tests readability of words vs punctuation at 13 pt."
        case .lcdStopwatch:
            "Seven-segment-ish digits in green on a dark plate, bracketed, no mark. Leans all the way into \"a stopwatch is running.\""
        case .liveDot:
            "Mark + time with a dot between them: filled red while you're actively watching, grey when idle. The only variant that shows counting vs paused."
        case .blinkingColon:
            "Minimal and width-locked: 1:05 where the colon blinks once a second while counting. The blink is the identity; no mark."
        }
    }

    /// Monochrome variants render as template images (free light/dark menu-bar
    /// inversion). The rest carry colour and render as-is.
    var isMonochrome: Bool {
        switch self {
        case .inlineTrailing, .timeOnly, .stackedMicro, .markAsSeparator,
             .unitSuffixed, .blinkingColon:
            true
        case .reversedPill, .goalRing, .lcdStopwatch, .liveDot:
            false
        }
    }
}

private let barFont = Font.system(size: 13, weight: .regular, design: .rounded)

/// One variant, laid out for a menu-bar-height slot. Pure function of the
/// inputs so the gallery and the live status item share it.
struct VariantLabel: View {
    let variant: IconTimeVariant
    let seconds: Int
    let isCounting: Bool
    let colonOn: Bool
    var goalHours: Double = 3

    private var t: TimeParts { TimeParts(seconds: seconds) }

    var body: some View {
        Group {
            switch variant {
            case .inlineTrailing:  inlineTrailing
            case .timeOnly:        timeOnly
            case .reversedPill:    reversedPill
            case .stackedMicro:    stackedMicro
            case .markAsSeparator: markAsSeparator
            case .goalRing:        goalRing
            case .unitSuffixed:    unitSuffixed
            case .lcdStopwatch:    lcdStopwatch
            case .liveDot:         liveDot
            case .blinkingColon:   blinkingColon
            }
        }
        .fixedSize()
    }

    private var inlineTrailing: some View {
        HStack(spacing: 4) {
            LogPlayMark(size: 13, color: .primary)
            Text(t.compact).font(barFont).monospacedDigit()
        }
    }

    private var timeOnly: some View {
        Text(t.compact).font(barFont).monospacedDigit()
    }

    private var reversedPill: some View {
        HStack(spacing: 3) {
            LogPlayMark(size: 9, color: .white)
            Text(t.compact)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(AppLogoTheme.accent))
    }

    private var stackedMicro: some View {
        HStack(spacing: 3) {
            LogPlayMark(size: 15, color: .primary)
            VStack(alignment: .leading, spacing: 0) {
                Text("WATCHED")
                    .font(.system(size: 6, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(t.compact)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var markAsSeparator: some View {
        if t.underHour {
            Text("\(t.totalMinutes)m").font(barFont).monospacedDigit()
        } else {
            HStack(spacing: 2) {
                Text("\(t.h)").font(barFont).monospacedDigit()
                LogPlayMark(size: 9, color: .primary)
                Text(t.mm).font(barFont).monospacedDigit()
            }
        }
    }

    private var goalRing: some View {
        let frac = min(1, Double(seconds) / max(1, goalHours * 3600))
        return HStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(AppLogoTheme.accent,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                LogPlayMark(size: 8, color: .primary)
            }
            .frame(width: 15, height: 15)
            Text(t.compact).font(barFont).monospacedDigit()
        }
    }

    @ViewBuilder
    private var unitSuffixed: some View {
        let unitFont = Font.system(size: 9, weight: .medium, design: .rounded)
        HStack(spacing: 4) {
            LogPlayMark(size: 13, color: .primary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if t.underHour {
                    Text("\(t.totalMinutes)").font(barFont).monospacedDigit()
                    Text("min").font(unitFont).foregroundStyle(.secondary)
                } else {
                    Text("\(t.h)").font(barFont).monospacedDigit()
                    Text("h").font(unitFont).foregroundStyle(.secondary)
                    Text(t.mm).font(barFont).monospacedDigit()
                }
            }
        }
    }

    private var lcdStopwatch: some View {
        let mono = Font.system(size: 12, weight: .bold, design: .monospaced)
        return HStack(spacing: 2) {
            Text("[").font(mono.weight(.light)).foregroundStyle(AppLogoTheme.lcdGreen.opacity(0.6))
            Text(t.clockString).font(mono).tracking(1).foregroundStyle(AppLogoTheme.lcdGreen)
            Text("]").font(mono.weight(.light)).foregroundStyle(AppLogoTheme.lcdGreen.opacity(0.6))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.82)))
    }

    private var liveDot: some View {
        HStack(spacing: 4) {
            LogPlayMark(size: 13, color: .primary)
            Circle()
                .fill(isCounting ? Color.red : Color.secondary)
                .frame(width: 5, height: 5)
            Text(t.compact).font(barFont).monospacedDigit()
        }
    }

    private var blinkingColon: some View {
        // Always the colon form, so there is a separator to blink.
        HStack(spacing: 0) {
            Text(t.underHour ? "0" : "\(t.h)").font(barFont).monospacedDigit()
            Text(":").font(barFont).opacity(colonOn || !isCounting ? 1 : 0)
            Text(t.underHour ? String(format: "%02d", t.totalMinutes) : t.mm)
                .font(barFont).monospacedDigit()
        }
    }
}

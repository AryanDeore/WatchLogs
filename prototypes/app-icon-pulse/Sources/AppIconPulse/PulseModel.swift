import AppKit
import Foundation
import SwiftUI

// MARK: - Parameters

enum PulseWaveform: String, CaseIterable, Identifiable {
    case sine, triangle, ease, breathe, heartbeat
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sine:      "Sine"
        case .triangle:  "Triangle"
        case .ease:      "Ease"
        case .breathe:   "Breathe"
        case .heartbeat: "Heartbeat"
        }
    }
}

enum PulseTint: String, CaseIterable, Identifiable {
    case none, accent, red, green, amber
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:   "None"
        case .accent: "Blue"
        case .red:    "Red"
        case .green:  "Green"
        case .amber:  "Amber"
        }
    }
    var nsColor: NSColor {
        switch self {
        case .none:   .labelColor
        case .accent: NSColor(srgbRed: 0x3b / 255, green: 0x6e / 255, blue: 0xf5 / 255, alpha: 1)
        case .red:    NSColor(srgbRed: 0.90, green: 0.26, blue: 0.21, alpha: 1)
        case .green:  NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .amber:  NSColor(srgbRed: 0.98, green: 0.70, blue: 0.16, alpha: 1)
        }
    }
}

enum TimeStyle: String, CaseIterable, Identifiable {
    case underHour, overHour
    var id: String { rawValue }
    var label: String { self == .underHour ? "47min" : "1h05" }
}

struct PulseParams: Equatable {
    var periodSeconds: Double
    var minOpacity: Double
    var waveform: PulseWaveform
    var pulseScale: Bool
    var minScale: Double
    var tint: PulseTint
    var tintStrength: Double
    var tintPulses: Bool

    /// Waveform value for a phase in 0...1. 1 = full brightness (peak),
    /// 0 = deepest fade (trough). Every shape starts and ends at the peak.
    func intensity(at phase: Double) -> Double {
        let p = phase - phase.rounded(.down)
        switch waveform {
        case .sine:
            return 0.5 + 0.5 * cos(2 * .pi * p)
        case .triangle:
            return abs(2 * p - 1)
        case .ease:
            let tri = abs(2 * p - 1)
            return tri * tri * (3 - 2 * tri)
        case .breathe:
            // Bright, quick-ish fade to a trough at 45% of the cycle, slow rise back.
            if p < 0.45 {
                return 1 - smoothstep(p / 0.45)
            } else {
                return smoothstep((p - 0.45) / 0.55)
            }
        case .heartbeat:
            let a = gaussian(p, center: 0.10, sigma: 0.045)
            let b = gaussian(p, center: 0.26, sigma: 0.055)
            return max(0, 1 - 0.85 * a - 0.55 * b)
        }
    }
}

private func smoothstep(_ x: Double) -> Double {
    let c = min(1, max(0, x))
    return c * c * (3 - 2 * c)
}

private func gaussian(_ x: Double, center: Double, sigma: Double) -> Double {
    exp(-pow(x - center, 2) / (2 * sigma * sigma))
}

// MARK: - Sample

struct PulseSample {
    var opacity: Double
    var scale: Double
    /// nil => render with `.primary` (template-friendly). Non-nil => concrete
    /// tinted colour, rendered non-template.
    var color: Color?
    var intensity: Double
}

// MARK: - Presets

struct PulsePreset: Identifiable {
    let name: String
    let blurb: String
    let params: PulseParams
    var id: String { name }
}

enum PulsePresets {
    /// Gentle breathing, opacity only, no colour, slow. Never drops below ~45%
    /// so the mark stays readable; slow enough not to nag; stays a monochrome
    /// template icon that follows the system menu bar. This is the default.
    static let recommended = PulseParams(
        periodSeconds: 2.6, minOpacity: 0.45, waveform: .breathe,
        pulseScale: false, minScale: 0.94, tint: .none, tintStrength: 0.7, tintPulses: false
    )

    static let all: [PulsePreset] = [
        PulsePreset(
            name: "Recommended",
            blurb: "Slow breathe, 45% trough, no colour. Reads as \u{201c}alive\u{201d} without nagging.",
            params: recommended
        ),
        PulsePreset(
            name: "Subtle",
            blurb: "Barely-there sine, 62% trough, 3.4 s. For people who find any motion distracting.",
            params: PulseParams(
                periodSeconds: 3.4, minOpacity: 0.62, waveform: .sine,
                pulseScale: false, minScale: 0.94, tint: .none, tintStrength: 0.7, tintPulses: false
            )
        ),
        PulsePreset(
            name: "Accent glow",
            blurb: "Blue that swells with the beat. Non-template, so it keeps its colour in light and dark.",
            params: PulseParams(
                periodSeconds: 2.2, minOpacity: 0.55, waveform: .sine,
                pulseScale: false, minScale: 0.94, tint: .accent, tintStrength: 0.75, tintPulses: true
            )
        ),
        PulsePreset(
            name: "Heartbeat",
            blurb: "Double-tap pulse with a tiny size dip. Distinct and playful; more attention-grabbing.",
            params: PulseParams(
                periodSeconds: 1.8, minOpacity: 0.40, waveform: .heartbeat,
                pulseScale: true, minScale: 0.93, tint: .none, tintStrength: 0.7, tintPulses: false
            )
        ),
        PulsePreset(
            name: "Static",
            blurb: "No visible pulse (100% trough). The \u{201c}off\u{201d} baseline to compare against.",
            params: PulseParams(
                periodSeconds: 2.6, minOpacity: 1.0, waveform: .sine,
                pulseScale: false, minScale: 1.0, tint: .none, tintStrength: 0, tintPulses: false
            )
        ),
    ]
}

// MARK: - Model

@Observable
@MainActor
final class PulseModel {
    static let shared = PulseModel()

    var isPlaying = true
    var timeStyle: TimeStyle = .overHour
    var params = PulsePresets.recommended
    var activePreset: String? = "Recommended"

    func apply(_ preset: PulsePreset) {
        params = preset.params
        activePreset = preset.name
    }

    /// Call after any manual slider/picker edit so the preset chip clears.
    func markCustom() {
        if PulsePresets.all.first(where: { $0.params == params })?.name == nil {
            activePreset = nil
        }
    }

    func phase(at date: Date) -> Double {
        let period = max(0.2, params.periodSeconds)
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    func sample(at date: Date, scheme: ColorScheme) -> PulseSample {
        guard isPlaying else {
            return PulseSample(opacity: 1, scale: 1, color: nil, intensity: 1)
        }
        let i = min(1, max(0, params.intensity(at: phase(at: date))))
        let opacity = params.minOpacity + (1 - params.minOpacity) * i
        let scale = params.pulseScale ? (params.minScale + (1 - params.minScale) * i) : 1

        var color: Color?
        if params.tint != .none, params.tintStrength > 0 {
            let mix = params.tintPulses
                ? params.tintStrength * (0.35 + 0.65 * i)
                : params.tintStrength
            color = Self.blend(resolvedLabelColor(scheme), params.tint.nsColor, CGFloat(mix))
        }
        return PulseSample(opacity: opacity, scale: scale, color: color, intensity: i)
    }

    // MARK: colour helpers

    private func resolvedLabelColor(_ scheme: ColorScheme) -> NSColor {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        var c = NSColor.labelColor
        appearance?.performAsCurrentDrawingAppearance { c = NSColor.labelColor }
        return c.usingColorSpace(.sRGB)
            ?? NSColor(white: scheme == .dark ? 0.95 : 0.1, alpha: 1)
    }

    private static func blend(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> Color {
        let a = a.usingColorSpace(.sRGB) ?? a
        let b = b.usingColorSpace(.sRGB) ?? b
        return Color(
            .sRGB,
            red: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            opacity: 1
        )
    }

    var swiftLiteral: String {
        """
        PulseParams(
            periodSeconds: \(String(format: "%.2f", params.periodSeconds)),
            minOpacity: \(String(format: "%.2f", params.minOpacity)),
            waveform: .\(params.waveform.rawValue),
            pulseScale: \(params.pulseScale),
            minScale: \(String(format: "%.2f", params.minScale)),
            tint: .\(params.tint.rawValue),
            tintStrength: \(String(format: "%.2f", params.tintStrength)),
            tintPulses: \(params.tintPulses)
        )
        """
    }
}

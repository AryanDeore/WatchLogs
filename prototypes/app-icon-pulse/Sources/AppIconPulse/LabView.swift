import AppKit
import SwiftUI

struct LabView: View {
    @Bindable var model: PulseModel

    var body: some View {
        TimelineView(.animation) { ctx in
            let now = ctx.date
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview(now: now)
                    Divider()
                    presets
                    Divider()
                    controls
                    Divider()
                    footer
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, minHeight: 720)
    }

    // MARK: preview

    @ViewBuilder
    private func preview(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pulse the icon while a video plays")
                .font(.title3.weight(.semibold))

            HStack(alignment: .top, spacing: 20) {
                // Magnified mark.
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .textBackgroundColor))
                    PulsingMark(size: 120, sample: model.sample(at: now, scheme: .light))
                        .environment(\.colorScheme, .light)
                }
                .frame(width: 190, height: 190)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.gray.opacity(0.2)))

                VStack(alignment: .leading, spacing: 10) {
                    Text("At menu-bar size").font(.caption).foregroundStyle(.secondary)
                    menuTile(dark: false, zoom: 1, now: now)
                    menuTile(dark: true, zoom: 1, now: now)
                    menuTile(dark: false, zoom: 2, now: now)
                }
            }

            waveformPlot(now: now)
        }
    }

    private func menuTile(dark: Bool, zoom: CGFloat, now: Date) -> some View {
        let w: CGFloat = zoom == 1 ? 150 : 260
        let h: CGFloat = 28 * zoom
        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(dark ? Color.black : Color.white)
                PulseMenuLabel(
                    sample: model.sample(at: now, scheme: dark ? .dark : .light),
                    timeStyle: model.timeStyle
                )
                .environment(\.colorScheme, dark ? .dark : .light)
                .scaleEffect(zoom)
            }
            .frame(width: w, height: h)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray.opacity(0.25)))
            Text(zoom == 1 ? (dark ? "dark" : "light") : "2\u{00d7}")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func waveformPlot(now: Date) -> some View {
        let params = model.params
        let playing = model.isPlaying
        let phaseNow = model.phase(at: now)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Opacity over one cycle").font(.caption).foregroundStyle(.secondary)
            Canvas { gctx, size in
                let steps = 200
                var path = Path()
                for k in 0...steps {
                    let p = Double(k) / Double(steps)
                    let i = playing ? params.intensity(at: p) : 1
                    let op = playing ? params.minOpacity + (1 - params.minOpacity) * i : 1
                    let pt = CGPoint(x: size.width * p, y: size.height * (1 - op))
                    if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                gctx.stroke(path, with: .color(Color.accentColor), lineWidth: 2)

                // trough guide line
                let troughY = size.height * (1 - params.minOpacity)
                var guide = Path()
                guide.move(to: CGPoint(x: 0, y: troughY))
                guide.addLine(to: CGPoint(x: size.width, y: troughY))
                gctx.stroke(guide, with: .color(.secondary.opacity(0.4)),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // playhead
                if playing {
                    var head = Path()
                    head.move(to: CGPoint(x: size.width * phaseNow, y: 0))
                    head.addLine(to: CGPoint(x: size.width * phaseNow, y: size.height))
                    gctx.stroke(head, with: .color(.secondary), lineWidth: 1)
                }
            }
            .frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.2)))
        }
    }

    // MARK: presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets").font(.headline)
            HStack {
                ForEach(PulsePresets.all) { preset in
                    Button {
                        model.apply(preset)
                    } label: {
                        Text(preset.name)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.activePreset == preset.name ? PulsePalette.accent : nil)
                }
            }
            if let name = model.activePreset,
               let blurb = PulsePresets.all.first(where: { $0.name == name })?.blurb {
                Text(blurb).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Custom \u{2014} tweaked from a preset.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Simulate video playing", isOn: $model.isPlaying)

            Picker("Readout", selection: $model.timeStyle) {
                ForEach(TimeStyle.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            slider("Cycle length", value: $model.params.periodSeconds,
                   range: 0.5...4.0, display: String(format: "%.1f s", model.params.periodSeconds))

            slider("Fade depth (trough opacity)", value: $model.params.minOpacity,
                   range: 0.1...1.0,
                   display: "\(Int(model.params.minOpacity * 100))%",
                   help: "100% = no fade")

            Picker("Waveform", selection: $model.params.waveform) {
                ForEach(PulseWaveform.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.params.waveform) { model.markCustom() }

            Toggle("Also pulse size", isOn: $model.params.pulseScale)
                .onChange(of: model.params.pulseScale) { model.markCustom() }
            slider("Min size", value: $model.params.minScale, range: 0.80...1.0,
                   display: "\(Int(model.params.minScale * 100))%")
                .disabled(!model.params.pulseScale)

            Picker("Tint", selection: $model.params.tint) {
                ForEach(PulseTint.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.params.tint) { model.markCustom() }

            slider("Tint strength", value: $model.params.tintStrength, range: 0...1,
                   display: "\(Int(model.params.tintStrength * 100))%")
                .disabled(model.params.tint == .none)

            Toggle("Tint swells with the beat", isOn: $model.params.tintPulses)
                .onChange(of: model.params.tintPulses) { model.markCustom() }
                .disabled(model.params.tint == .none)
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String,
        help: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(display).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
            Slider(value: value, in: range) { editing in
                if !editing { model.markCustom() }
            }
            if let help {
                Text(help).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Button("Copy parameters") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.swiftLiteral, forType: .string)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

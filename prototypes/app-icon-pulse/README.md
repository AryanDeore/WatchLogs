# Prototype: pulsing the menu-bar icon while a video plays

**Decision so far.** From `prototypes/app-icon-time`, variant 7 ("unit
suffixed" — `47min` / `1h05`, play mark prefix) won.

**Question this prototype answers.** While a video is actually playing, the
*mark* (not the numbers) should pulse to signal "capture is live." What fade
depth, speed, waveform and colour feel right — subtle enough to ignore,
clear enough to notice?

## Verdict

Chosen: **"Recommended" with a symmetric eased waveform** (picked `.ease` over
`.breathe` — equal fade-out / fade-in reads calmer than the asymmetric one).

```swift
PulseParams(
    periodSeconds: 2.60,
    minOpacity: 0.45,
    waveform: .ease,
    pulseScale: false,
    minScale: 0.94,   // unused (pulseScale: false)
    tint: .none,
    tintStrength: 0.70, // unused (tint: .none)
    tintPulses: false
)
```

Monochrome (template icon, follows the system menu bar), 2.6 s cycle, never
below 45% opacity, no size change. Pulse is gated on a real "video is playing"
signal from the extension; paused = static plain mark.

## Run it

```
cd prototypes/app-icon-pulse
swift run
```

A status item appears in the menu bar (variant 7, mark pulsing) and the **Icon
pulse lab** window opens. Clicking the status item just re-focuses the lab.

## What you can tune

- **Simulate video playing** — off = static plain mark (the paused state).
- **Readout** — `47min` vs `1h05`, to check the mark against both widths.
- **Cycle length** — one full breathe, 0.5–4.0 s.
- **Fade depth** — opacity at the trough. 100% = no fade; lower = deeper dip.
- **Waveform** — Sine, Triangle, Ease, Breathe (asymmetric: quick out, slow
  in), Heartbeat (double-tap then a long hold).
- **Also pulse size** + **Min size** — optional scale breathing, 80–100%.
- **Tint** — None (monochrome template icon) or Blue / Red / Green / Amber.
- **Tint strength** and **Tint swells with the beat** — steady wash vs a
  colour glow that peaks with the pulse.

The **opacity-over-one-cycle** plot under the previews shows the current
waveform, the trough line, and a moving playhead. **Copy parameters** puts a
`PulseParams(...)` Swift literal on the clipboard.

## Recommended presets (in the prototype)

| Preset | Feel | Params |
|---|---|---|
| **Recommended** | "Alive, not nagging." Slow breathe, stays readable, stays monochrome. | 2.6 s · trough 45% · Breathe · no colour |
| **Subtle** | For anyone who finds motion distracting. | 3.4 s · trough 62% · Sine |
| **Accent glow** | Colour that swells with the beat; keeps its hue in light & dark (non-template). | 2.2 s · trough 55% · Sine · Blue 75% · pulsing |
| **Heartbeat** | Distinct, playful, more attention-grabbing. | 1.8 s · trough 40% · Heartbeat · size 93–100% |
| **Static** | The "off" baseline to compare against. | trough 100% · no colour |

**Recommendation: "Recommended".** A slow asymmetric breathe that never drops
the mark below ~45% opacity reads as a live indicator without pulling the eye,
and keeping it colourless means the icon still follows the system menu bar
(template image, automatic light/dark). Colour (Accent glow) is the runner-up
if the pulse needs to be noticeable from across the room; the cost is the icon
no longer being a neutral template.

## Status

Throwaway. Wall-clock-driven sim, no real playback signal. Whatever preset
wins gets folded into the real menu-bar view as the "playing" animation, with
the pulse gated on an actual "video is playing" event from the extension.

import AppKit

/// The menu-bar mark (Concept A from `prototypes/app-logo-concepts/`, the
/// stepped-bars log/play mark) and the composite that pairs it with a
/// watched-time readout.
///
/// MenuBarExtra's custom-View label path is unreliable for bare SwiftUI shapes
/// and TimelineViews (the slot can render blank — see
/// `prototypes/app-icon-time/`), so everything here is drawn as a real template
/// `NSImage`. Template images get light/dark menu-bar inversion for free, and
/// the App just swaps the image as the readout ticks and the mark pulses.
extension NSImage {
    /// The bare mark, no readout.
    static func logPlayMarkTemplate(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            drawLogPlayBars(in: rect, alpha: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Menu-bar label: the mark, then today's watched time in the "unit
    /// suffixed" style chosen in `prototypes/app-icon-time/` — `47min` under an
    /// hour, `1h05` at or over one. Only the mark carries `markOpacity`; the
    /// readout is always fully opaque. The pulse itself (period, depth, easing)
    /// lives in `MenuBarIconModel`.
    static func watchLogsMenuBar(
        watchedMs: Int,
        markOpacity: Double,
        display: AppSettings.IconDisplay = .iconAndTime,
        separator: AppSettings.TimeSeparator = .letter,
        blinkSeparator: Bool = false
    ) -> NSImage {
        let height: CGFloat = 15
        let markSize: CGFloat = 13
        let gap: CGFloat = 4
        
        switch display {
        case .iconOnly:
            // Just the mark, no readout
            let image = NSImage(size: NSSize(width: markSize, height: height), flipped: false) { rect in
                let markRect = NSRect(
                    x: 0,
                    y: (rect.height - markSize) / 2,
                    width: markSize,
                    height: markSize
                )
                drawLogPlayBars(in: markRect, alpha: max(0, min(1, markOpacity)))
                return true
            }
            image.isTemplate = true
            return image
            
        case .timeOnly:
            // Just the time, no mark
            let text = menuBarWatchedString(watchedMs: watchedMs, separator: separator, blinkSeparator: blinkSeparator)
            let textSize = text.size()
            let width = textSize.width.rounded(.up)
            
            let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
                text.draw(at: NSPoint(
                    x: 0,
                    y: (rect.height - textSize.height) / 2
                ))
                return true
            }
            image.isTemplate = true
            return image
            
        case .iconAndTime:
            // Mark + time (the default, original behavior)
            let text = menuBarWatchedString(watchedMs: watchedMs, separator: separator, blinkSeparator: blinkSeparator)
            let textSize = text.size()
            let width = (markSize + gap + textSize.width).rounded(.up)

            let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
                let markRect = NSRect(
                    x: 0,
                    y: (rect.height - markSize) / 2,
                    width: markSize,
                    height: markSize
                )
                drawLogPlayBars(in: markRect, alpha: max(0, min(1, markOpacity)))
                text.draw(at: NSPoint(
                    x: markSize + gap,
                    y: (rect.height - textSize.height) / 2
                ))
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    // MARK: - Drawing

    /// Three stepped bars: reads as a log list and as a play triangle.
    /// `yFraction` is measured from the top, matching the SwiftUI prototype;
    /// AppKit's default space is bottom-origin.
    private static func drawLogPlayBars(in rect: NSRect, alpha: CGFloat) {
        NSColor.black.withAlphaComponent(alpha).setFill()
        let leftInset = rect.minX + rect.width * 0.24
        let barHeight = rect.height * 0.15

        func bar(widthFraction: CGFloat, yFraction: CGFloat) {
            let width = rect.width * widthFraction
            let y = rect.minY + rect.height * (1 - yFraction) - barHeight / 2
            let barRect = NSRect(x: leftInset, y: y, width: width, height: barHeight)
            NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        }

        bar(widthFraction: 0.26, yFraction: 0.28)
        bar(widthFraction: 0.52, yFraction: 0.50)
        bar(widthFraction: 0.26, yFraction: 0.72)
    }

    /// `47min` / `1h05`, digits monospaced and rounded, the unit in a lighter
    /// weight — one attributed string so the unit sits on the digits' baseline.
    /// Supports both letter separator (1h05) and colon separator (1:05), with
    /// optional blinking of the colon.
    private static func menuBarWatchedString(
        watchedMs: Int,
        separator: AppSettings.TimeSeparator,
        blinkSeparator: Bool
    ) -> NSAttributedString {
        let minutes = max(0, watchedMs) / 60_000
        let digitFont = roundedMonospacedDigitFont(size: 12, weight: .regular)
        let unitFont = roundedMonospacedDigitFont(size: 8.5, weight: .medium)
        let digits: [NSAttributedString.Key: Any] = [.font: digitFont, .foregroundColor: NSColor.black]
        let unit: [NSAttributedString.Key: Any] = [
            .font: unitFont,
            .foregroundColor: NSColor.black.withAlphaComponent(0.55),
        ]

        let result = NSMutableAttributedString()
        if minutes < 60 {
            // Under an hour: always bare minutes ("47min")
            result.append(NSAttributedString(string: "\(minutes)", attributes: digits))
            result.append(NSAttributedString(string: "min", attributes: unit))
        } else {
            // At or over an hour: apply separator style
            switch separator {
            case .letter:
                // 1h05 format
                result.append(NSAttributedString(string: "\(minutes / 60)", attributes: digits))
                result.append(NSAttributedString(string: "h", attributes: unit))
                result.append(NSAttributedString(string: String(format: "%02d", minutes % 60), attributes: digits))
            case .colon:
                // 1:05 format, with optional blinking
                result.append(NSAttributedString(string: "\(minutes / 60)", attributes: digits))
                // Colon blinks at 1 Hz when blinkSeparator is true
                let colonVisible = !blinkSeparator || Int(Date().timeIntervalSinceReferenceDate) % 2 == 0
                let colonOpacity = colonVisible ? 1.0 : 0.0
                let colonAttrs: [NSAttributedString.Key: Any] = [
                    .font: digitFont,
                    .foregroundColor: NSColor.black.withAlphaComponent(colonOpacity),
                ]
                result.append(NSAttributedString(string: ":", attributes: colonAttrs))
                result.append(NSAttributedString(string: String(format: "%02d", minutes % 60), attributes: digits))
            }
        }
        return result
    }

    private static func roundedMonospacedDigitFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size)
        else { return base }
        return rounded
    }
}

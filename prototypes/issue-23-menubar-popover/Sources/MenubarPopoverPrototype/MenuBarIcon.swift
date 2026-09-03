import AppKit

// Lifted from prototypes/app-logo-concepts/ (concept A, LogPlayMark): three
// stepped bars that read both as a list of log entries and as a play
// triangle. Concept B, the Watch_Dogs-pun mark, reads better at this size but
// carries a trademark question that concept A does not.
//
// MenuBarExtra's custom-View label path is unreliable for a bare SwiftUI
// Shape (it can occupy the status-item slot but paint nothing). Drawing a
// real template NSImage is the well-trodden path, and it gets automatic
// light/dark menu-bar inversion for free.
extension NSImage {
    static func logPlayMarkTemplate(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            NSColor.black.setFill()
            let leftInset = rect.width * 0.24
            let barHeight = rect.height * 0.15

            // yFraction measured from the top, matching LogPlayMark's SwiftUI
            // layout; AppKit's default coordinate space is bottom-origin.
            func drawBar(widthFraction: CGFloat, yFraction: CGFloat) {
                let width = rect.width * widthFraction
                let y = rect.height * (1 - yFraction) - barHeight / 2
                let barRect = NSRect(x: leftInset, y: y, width: width, height: barHeight)
                NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
            }

            drawBar(widthFraction: 0.26, yFraction: 0.28)
            drawBar(widthFraction: 0.52, yFraction: 0.50)
            drawBar(widthFraction: 0.26, yFraction: 0.72)
            return true
        }
        image.isTemplate = true
        return image
    }
}

import SwiftUI

// macOS's overlay scroller is sized for a document window; inside a 380pt
// popover it reads as a heavy vertical stripe. AppKit exposes no knob-width
// knob, so this hides the system indicator and draws its own at ~2.5pt
// against the stock ~7pt knob.
struct ThinScrollView<Content: View>: View {
    private let content: Content
    private let onContentHeightChange: (CGFloat) -> Void
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    init(onContentHeightChange: @escaping (CGFloat) -> Void = { _ in }, @ViewBuilder content: () -> Content) {
        self.onContentHeightChange = onContentHeightChange
        self.content = content()
    }

    private var knobFraction: CGFloat {
        guard contentHeight > 0 else { return 1 }
        return min(1, viewportHeight / contentHeight)
    }

    private var scrollFraction: CGFloat {
        let scrollable = contentHeight - viewportHeight
        guard scrollable > 0 else { return 0 }
        return min(1, max(0, scrollOffset / scrollable))
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                content
                    .background {
                        GeometryReader { inner in
                            Color.clear
                                .onAppear {
                                    contentHeight = inner.size.height
                                    onContentHeightChange(inner.size.height)
                                    scrollOffset = -inner.frame(in: .named("thinScroll")).minY
                                }
                                .onChange(of: inner.frame(in: .named("thinScroll")).minY) { _, newValue in
                                    scrollOffset = -newValue
                                }
                                .onChange(of: inner.size.height) { _, newValue in
                                    contentHeight = newValue
                                    onContentHeightChange(newValue)
                                }
                        }
                    }
                    .background { ScrollerHider() }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "thinScroll")
            .overlay(alignment: .topTrailing) {
                if knobFraction < 1 {
                    let trackHeight = viewport.size.height - 8
                    let knobHeight = max(24, trackHeight * knobFraction)
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 2.5, height: knobHeight)
                        .offset(
                            x: -3,
                            y: 4 + (trackHeight - knobHeight) * scrollFraction
                        )
                }
            }
            .onAppear { viewportHeight = viewport.size.height }
            .onChange(of: viewport.size.height) { _, newValue in viewportHeight = newValue }
        }
    }
}

// `.scrollIndicators(.hidden)` was not enough on its own: the AppKit overlay
// scroller still faded in on hover/scroll, drawing its light full-height track
// and its own knob behind this one — two bars, the system's the wider of the
// two. The modifier doesn't reach `NSScrollView.hasVerticalScroller`, so this
// walks up to the scroll view and clears it directly. Zero-size, sits in the
// content's background purely to get an `enclosingScrollView`.
//
// SwiftUI re-enables the scroller every time it re-lays the ScrollView — which
// now happens on the 5-second refresh tick and whenever the pane's height
// changes — so clearing it once on `viewDidMoveToWindow` isn't enough. This
// re-clears on every frame change of the scroll view and its document view,
// which is what those relayouts post.
private struct ScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HidingView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? HidingView)?.hideScrollers()
    }

    private final class HidingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideScrollers()

            let center = NotificationCenter.default
            center.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
            guard let scrollView = enclosingScrollView else { return }
            // NotificationCenter holds `self` unowned here and drops the
            // registration when this view deallocates — no manual teardown.
            for object in [scrollView, scrollView.documentView].compactMap({ $0 }) {
                object.postsFrameChangedNotifications = true
                center.addObserver(
                    self, selector: #selector(frameChanged),
                    name: NSView.frameDidChangeNotification, object: object
                )
            }
        }

        @objc private func frameChanged() { hideScrollers() }

        func hideScrollers() {
            guard let scrollView = enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.scrollerStyle = .overlay
        }
    }
}

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
private struct ScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HidingView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HidingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideScrollers()
            // The scroll view can re-enable its scrollers while laying out, so
            // clear them once more after this pass settles.
            DispatchQueue.main.async { [weak self] in self?.hideScrollers() }
        }

        private func hideScrollers() {
            guard let scrollView = enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.scrollerStyle = .overlay
        }
    }
}

import SwiftUI

// macOS's overlay scroller is sized for a document window; inside a 380pt
// popover it reads as a heavy vertical stripe. AppKit exposes no knob-width
// knob, so this hides the system indicator and draws its own at half the
// width (~3.5pt vs the stock ~7pt knob).
struct ThinScrollView<Content: View>: View {
    private let content: Content
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    init(@ViewBuilder content: () -> Content) {
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
                                    scrollOffset = -inner.frame(in: .named("thinScroll")).minY
                                }
                                .onChange(of: inner.frame(in: .named("thinScroll")).minY) { _, newValue in
                                    scrollOffset = -newValue
                                }
                                .onChange(of: inner.size.height) { _, newValue in
                                    contentHeight = newValue
                                }
                        }
                    }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "thinScroll")
            .overlay(alignment: .topTrailing) {
                if knobFraction < 1 {
                    let trackHeight = viewport.size.height - 8
                    let knobHeight = max(24, trackHeight * knobFraction)
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 3.5, height: knobHeight)
                        .offset(
                            x: -2.5,
                            y: 4 + (trackHeight - knobHeight) * scrollFraction
                        )
                }
            }
            .onAppear { viewportHeight = viewport.size.height }
            .onChange(of: viewport.size.height) { _, newValue in viewportHeight = newValue }
        }
    }
}

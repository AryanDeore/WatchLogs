import SwiftUI

// "Measure my laid-out height and report it." PopoverView uses this on the
// chrome above the scroll area (title through tab bar, including the
// calendar's collapsed/expanded state) to size the window around whatever's
// actually on screen, rather than hardcoding a height per calendar state.
//
// Deliberately a GeometryReader + onAppear/onChange callback rather than a
// PreferenceKey: a preference set inside `.background` does not propagate
// back out to an `.onPreferenceChange` on the modified view, so the first
// version of this silently reported 0 forever and the window got sized as
// if the whole header didn't exist. This is the same shape ThinScrollView
// already uses to measure its content, which does work.
extension View {
    func measureHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onChange(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, newValue in onChange(newValue) }
            }
        }
    }
}

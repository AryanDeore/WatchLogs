import AppKit
import SwiftUI

// AppKit shell (same reasoning as prototypes/app-icon-time): MenuBarExtra's
// SwiftUI label paints unreliably in a bare SPM executable, so the status item
// is a real NSStatusItem whose image is re-rendered from `PulseMenuLabel` on a
// ~30 fps timer while "playing" is on.

@main
struct AppIconPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PulseModel.shared
    private var statusItem: NSStatusItem!
    private var labWindow: NSWindow!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(bringUpLab)

        labWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        labWindow.title = "Icon pulse lab"
        labWindow.contentViewController = NSHostingController(rootView: LabView(model: model))
        labWindow.center()
        labWindow.isReleasedWhenClosed = false

        refreshStatusItem()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatusItem() }
        }

        bringUpLab()
    }

    @objc private func bringUpLab() {
        labWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let tinted = model.isPlaying && model.params.tint != .none && model.params.tintStrength > 0
        let scheme: ColorScheme = tinted ? systemColorScheme : .light

        let label = PulseMenuLabel(
            sample: model.sample(at: .now, scheme: scheme),
            timeStyle: model.timeStyle
        )
        .padding(.horizontal, 2)
        .frame(height: 18)
        .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: label)
        renderer.scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        if let image = renderer.nsImage, image.size.width > 0 {
            image.isTemplate = !tinted
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = model.timeStyle == .underHour ? "47min" : "1h05"
        }
    }

    private var systemColorScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

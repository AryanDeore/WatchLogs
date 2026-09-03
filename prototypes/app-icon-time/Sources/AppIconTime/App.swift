import AppKit
import SwiftUI

// MenuBarExtra's SwiftUI-label path is unreliable in this repo (see
// app/Sources/WatchLogs/MenuBarIcon.swift) — a composed label can hold the
// status-item slot but paint nothing, which is exactly what happened here once
// the label was a TimelineView. So this prototype runs an AppKit shell: a real
// NSStatusItem whose image is rendered from the SwiftUI VariantLabel and
// refreshed on a timer, an NSPopover for the picker, and a plain NSWindow for
// the gallery.

@main
struct AppIconTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

extension Notification.Name {
    static let openGallery = Notification.Name("AppIconTime.openGallery")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PrototypeModel.shared
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var galleryWindow: NSWindow!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 470)
        popover.contentViewController = NSHostingController(rootView: PopoverContent(model: model))

        galleryWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        galleryWindow.title = "App-icon time prototypes"
        galleryWindow.contentViewController = NSHostingController(rootView: GalleryView(model: model))
        galleryWindow.center()
        galleryWindow.isReleasedWhenClosed = false

        NotificationCenter.default.addObserver(
            self, selector: #selector(showGallery), name: .openGallery, object: nil
        )

        refreshStatusItem()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatusItem() }
        }

        showGallery()
    }

    @objc private func showGallery() {
        galleryWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let now = Date.now
        let mono = model.selectedVariant.isMonochrome

        let label = VariantLabel(
            variant: model.selectedVariant,
            seconds: model.watchedSeconds(at: now),
            isCounting: model.isCounting,
            colonOn: Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0,
            goalHours: model.goalHours
        )
        .padding(.horizontal, 2)
        .frame(height: 18)
        .environment(\.colorScheme, mono ? .light : systemColorScheme)

        let renderer = ImageRenderer(content: label)
        renderer.scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        if let image = renderer.nsImage, image.size.width > 0 {
            image.isTemplate = mono
            button.image = image
            button.title = ""
        } else {
            // Last-ditch fallback so the slot is never blank.
            button.image = nil
            button.title = TimeParts(seconds: model.watchedSeconds(at: now)).compact
        }
    }

    private var systemColorScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

struct PopoverContent: View {
    @Bindable var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App-icon prototypes").font(.headline)
            Text("Ten takes on the menu-bar icon carrying a running watched-time readout. Pick one to preview it live above; open the gallery to compare all ten side by side.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Picker("Preview", selection: $model.selectedVariant) {
                ForEach(IconTimeVariant.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Toggle("Simulate watching (readout ticks up)", isOn: $model.counting)

            HStack {
                Button("Open gallery") {
                    NotificationCenter.default.post(name: .openGallery, object: nil)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

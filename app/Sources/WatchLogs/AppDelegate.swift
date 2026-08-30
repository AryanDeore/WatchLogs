import AppKit
import WatchLogsKit

/// The menubar App for issue #26's tracer bullet: it runs the loopback server,
/// shows the pairing string, and displays one status line.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var service: LoopbackService!
    private var refreshTimer: Timer?

    private let flushClock = LastFlushClock()

    private static let version = "0.1.0"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let clock = flushClock
        do {
            service = try LoopbackService(
                version: Self.version,
                tokenStore: KeychainTokenStore(),
                onFlush: {
                    clock.mark()
                    Task { @MainActor in AppDelegate.shared?.rebuildMenu() }
                }
            )
            try service.start()
        } catch {
            presentFatal("Could not start the WatchLogs server: \(error)")
            return
        }

        AppDelegate.shared = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Watch·Logs"
        rebuildMenu()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuildMenu() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        service?.stop()
    }

    /// The server's flush callback fires on a background queue; this weak
    /// main-actor handle lets it ask for a menu refresh without capturing `self`
    /// across the isolation boundary.
    private static weak var shared: AppDelegate?

    private func currentStatus() -> MenubarStatus {
        MenubarStatus.evaluate(lastFlushAt: flushClock.last, now: Date())
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let status = currentStatus()
        let statusRow = NSMenuItem(title: status.line, action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        menu.addItem(statusRow)

        let boundPort = service.server.boundPort.map(String.init) ?? "—"
        let portRow = NSMenuItem(title: "Listening on \(LoopbackDefaults.host):\(boundPort)", action: nil, keyEquivalent: "")
        portRow.isEnabled = false
        menu.addItem(portRow)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy Pairing String", action: #selector(copyPairingString), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Regenerate Token", action: #selector(regenerateToken), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit WatchLogs", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil && item.target == nil {
            item.target = self
        }
        statusItem.menu = menu

        if case .connected = status {
            statusItem.button?.title = "Watch·Logs ●"
        } else {
            statusItem.button?.title = "Watch·Logs ○"
        }
    }

    @objc private func copyPairingString() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(service.pairingString(), forType: .string)
    }

    @objc private func regenerateToken() {
        do {
            _ = try service.regenerateToken()
            copyPairingString()
            let alert = NSAlert()
            alert.messageText = "New pairing string copied"
            alert.informativeText = "The old token no longer works. Paste the new pairing string into the extension."
            alert.runModal()
        } catch {
            presentFatal("Could not regenerate the token: \(error)")
        }
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "WatchLogs"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}

/// Thread-safe holder for "when did the last Flush land". Written from the
/// server's background queue, read on the main thread.
final class LastFlushClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _last: Date?

    func mark() {
        lock.lock(); _last = Date(); lock.unlock()
    }

    var last: Date? {
        lock.lock(); defer { lock.unlock() }
        return _last
    }
}

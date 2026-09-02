import AppKit
import WatchLogsKit

/// The menubar App for issue #26's tracer bullet: it runs the loopback server,
/// shows the pairing string, and displays one status line.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var transport: LoopbackTransport!
    private var refreshTimer: Timer?

    /// When the last Flush landed. Written from the server's background queue,
    /// read here on the main thread.
    private let lastFlush = Locked<Date?>(nil)

    private static let version = "0.1.0"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let lastFlush = self.lastFlush
        do {
            transport = try LoopbackTransport(
                version: Self.version,
                tokenStore: KeychainTokenStore(),
                store: EventStore(path: try EventStore.defaultPath()),
                onFlush: {
                    lastFlush.set(Date())
                    Task { @MainActor in AppDelegate.shared?.rebuildMenu() }
                }
            )
            try transport.start()
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
        transport?.stop()
    }

    /// The server's flush callback fires on a background queue; this weak
    /// main-actor handle lets it ask for a menu refresh without capturing `self`
    /// across the isolation boundary.
    private static weak var shared: AppDelegate?

    private func currentStatus() -> MenubarStatus {
        MenubarStatus.evaluate(lastFlushAt: lastFlush.current, now: Date())
    }

    /// The headline number, or a short explanation of why there isn't one.
    private func watchedTodayLine() -> String {
        guard let totals = try? transport.todayTotals() else {
            return "Watched today · unavailable"
        }
        return WatchedTimeLine.today(totals)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let watchedRow = NSMenuItem(title: watchedTodayLine(), action: nil, keyEquivalent: "")
        watchedRow.isEnabled = false
        menu.addItem(watchedRow)

        let status = currentStatus()
        let statusRow = NSMenuItem(title: status.line, action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        menu.addItem(statusRow)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Pairing String…", action: #selector(showPairingString), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Regenerate Token", action: #selector(regenerateToken), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Day Boundary…", action: #selector(showDayBoundarySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Rebuild Statistics", action: #selector(rebuildStatistics), keyEquivalent: ""))
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

    /// The "Settings" surface for this slice: show the base64 pairing string in a
    /// selectable field, with a Copy button.
    @objc private func showPairingString() {
        let pairingString = transport.pairingString()

        let alert = NSAlert()
        alert.messageText = "Pairing string"
        alert.informativeText = "Paste this into the WatchLogs extension's Options to pair."
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Done")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 48))
        field.stringValue = pairingString
        field.isEditable = false
        field.isSelectable = true
        field.lineBreakMode = .byCharWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            copyToPasteboard(pairingString)
        }
    }

    /// The Day target hour (ADR 0001): a local hour a Day aims to end at,
    /// sliding later only while watched-time activity is still going. Takes
    /// effect for the currently open Day; a Day already frozen never moves.
    @objc private func showDayBoundarySettings() {
        let current = (try? transport.targetHour()) ?? DayBoundary.defaultTargetHour

        let alert = NSAlert()
        alert.messageText = "Day target hour"
        alert.informativeText = "A Day aims to end at this local hour (0–9) once nothing is playing. It slides later while you're still watching, capped at 10:00. Default is 4 (4:00 AM)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
        field.stringValue = "\(current)"
        alert.accessoryView = field

        // Must stay strictly before the fixed 10:00 cap, or the cap would
        // stop acting as a same-day backstop (DayBoundary derives it as an
        // offset from the target hour).
        guard alert.runModal() == .alertFirstButtonReturn,
              let hour = Int(field.stringValue),
              (0..<DayBoundary.hardCapHour).contains(hour)
        else { return }

        do {
            try transport.setTargetHour(hour)
        } catch {
            presentFatal("Could not save the Day target hour: \(error)")
        }
    }

    /// The manual "Rebuild statistics" action (ADR 0004): drops both rollup
    /// tables and replays them from `segments`, for when the cache is
    /// suspected stale.
    @objc private func rebuildStatistics() {
        do {
            try transport.rebuildStatistics()
            rebuildMenu()
        } catch {
            presentFatal("Could not rebuild statistics: \(error)")
        }
    }

    @objc private func regenerateToken() {
        do {
            let pairingString = try transport.regenerateToken()
            copyToPasteboard(pairingString)
            let alert = NSAlert()
            alert.messageText = "New pairing string copied"
            alert.informativeText = "The old token no longer works. Paste the new pairing string into the extension."
            alert.runModal()
        } catch {
            presentFatal("Could not regenerate the token: \(error)")
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "WatchLogs"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}

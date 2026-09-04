import AppKit
import Observation
import SwiftUI
import WatchLogsKit

@main
struct WatchLogsApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: controller.model, transport: controller.transport, settings: controller.settings)
        } label: {
            MenuBarIconLabel(iconModel: controller.iconModel)
        }
        .menuBarExtraStyle(.window)
    }
}

/// A thin view so the label subtree observes `iconModel.icon` and re-renders
/// when the readout ticks or the mark pulses.
struct MenuBarIconLabel: View {
    let iconModel: MenuBarIconModel

    var body: some View {
        Image(nsImage: iconModel.icon)
    }
}

@Observable
@MainActor
final class AppController {
    let transport: LoopbackTransport
    let model: MenubarPopoverReadModel
    let iconModel: MenuBarIconModel
    let settings: AppSettings

    init() {
        do {
            let transport = try LoopbackTransport(
                version: "0.1.0",
                tokenStore: KeychainTokenStore(),
                store: EventStore(path: try EventStore.defaultPath())
            )
            try transport.start()
            self.transport = transport
            self.model = MenubarPopoverReadModel(store: transport.store)
            self.settings = AppSettings()
            self.iconModel = MenuBarIconModel(
                transport: transport,
                settings: self.settings,
                forcePulse: ProcessInfo.processInfo.environment["WATCHLOGS_FORCE_PULSE"] == "1"
            )
            // Wire up settings changes to icon updates
            self.settings.onIconSettingsChanged = { [weak iconModel] in
                Task { @MainActor in
                    iconModel?.forceUpdate()
                }
            }
        } catch {
            fatalError("Could not start WatchLogs: \(error)")
        }
    }

    deinit { transport.stop() }
}

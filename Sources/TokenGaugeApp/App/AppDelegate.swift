import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    let launchAtLogin = LaunchAtLoginManager()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusController = StatusItemController(store: store, launchAtLogin: launchAtLogin)
        store.start()
    }
}

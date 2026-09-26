import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DemoData.isEnabled ? DemoData.makeStore() : UsageStore()
    let launchAtLogin = LaunchAtLoginManager()
    private var statusController: StatusItemController?
    private var wakeObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.accessory)
        statusController = StatusItemController(store: store, launchAtLogin: launchAtLogin)
        guard store.liveReadsEnabled else { return }
        store.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.store.refreshSoon(after: .seconds(3), force: false) }
        }
        UpdateManager.shared.start()
        requestClaudeRecoveryConsent()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.stop()
        guard ClaudeSessionRecovery.shared.isRunning else { return .terminateNow }
        Task {
            while ClaudeSessionRecovery.shared.isRunning {
                try? await Task.sleep(for: .milliseconds(50))
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func requestClaudeRecoveryConsent() {
        guard !AppPreferences().claudeAutomaticRecoveryDecided, ClaudeSessionRecovery.executable() != nil else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "setup.claude_recovery_title".localized
        alert.informativeText = "setup.claude_recovery_message".localized
        alert.addButton(withTitle: "setup.claude_recovery_allow".localized)
        alert.addButton(withTitle: "setup.claude_recovery_decline".localized)
        NSApp.activate(ignoringOtherApps: true)
        store.claudeAutomaticRecovery = alert.runModal() == .alertFirstButtonReturn
    }

    func showSettings() {
        statusController?.showSettings()
    }

    func showAbout() {
        statusController?.showAbout()
    }
}

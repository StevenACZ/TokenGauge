import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    let launchAtLogin = LaunchAtLoginManager()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusController = StatusItemController(store: store, launchAtLogin: launchAtLogin)
        requestClaudeRecoveryConsent()
        store.start()
        UpdateManager.shared.start()
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
        guard UserDefaults.standard.object(forKey: "claudeAutomaticRecovery") == nil,
            ClaudeSessionRecovery.executable() != nil
        else { return }
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

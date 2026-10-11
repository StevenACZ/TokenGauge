import AppKit
import Combine
import SwiftUI

@MainActor
final class AppWindows {
    private let store: UsageStore
    private let launchAtLogin: LaunchAtLoginManager
    private let navigation = SettingsNavigation()
    private var settings: NSWindow?
    private var languageObservation: AnyCancellable?

    init(store: UsageStore, launchAtLogin: LaunchAtLoginManager) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        languageObservation = LocalizationManager.shared.$bundle.sink { [weak self] bundle in
            self?.settings?.title = bundle.localizedString(forKey: "settings.title", value: nil, table: nil)
        }
    }

    func showSettings(_ page: SettingsPage? = nil) {
        if let page {
            navigation.page = page
        } else if settings?.isVisible != true {
            navigation.page = .menuBar
        }
        if settings == nil { settings = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        showSettings(.about)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "settings.title".localized
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: SettingsView(store: store, launchAtLogin: launchAtLogin, navigation: navigation))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(
            NSSize(
                width: SettingsView.width,
                height: min(SettingsView.height, (NSScreen.main?.visibleFrame.height ?? 900) - 40)))
        window.center()
        return window
    }
}

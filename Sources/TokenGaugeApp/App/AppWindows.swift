import AppKit
import Combine
import SwiftUI

@MainActor
final class AppWindows {
    private let store: UsageStore
    private let launchAtLogin: LaunchAtLoginManager
    private var settings: NSWindow?
    private var about: NSWindow?
    private var languageObservation: AnyCancellable?

    init(store: UsageStore, launchAtLogin: LaunchAtLoginManager) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        languageObservation = LocalizationManager.shared.$bundle.sink { [weak self] bundle in
            self?.settings?.title = bundle.localizedString(forKey: "settings.title", value: nil, table: nil)
            self?.about?.title = bundle.localizedString(forKey: "about.title", value: nil, table: nil)
        }
    }

    func showSettings() {
        if settings == nil {
            settings = makeWindow(
                title: "settings.title".localized, size: NSSize(width: 600, height: 750),
                view: SettingsView(store: store, launchAtLogin: launchAtLogin))
        }
        present(settings)
    }

    func showAbout() {
        if about == nil {
            about = makeWindow(title: "about.title".localized, size: NSSize(width: 420, height: 560), view: AboutView())
        }
        present(about)
    }

    private func makeWindow(title: String, size: NSSize, view: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: ScrollView { view }.scrollIndicators(.automatic))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(
            NSSize(width: size.width, height: min(size.height, (NSScreen.main?.visibleFrame.height ?? 900) - 40)))
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: UsageStore
    private let launchAtLogin: LaunchAtLoginManager
    private var cancellables = Set<AnyCancellable>()
    private var renderedRemaining: Int?

    init(store: UsageStore, launchAtLogin: LaunchAtLoginManager) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
        }

        Publishers.CombineLatest(store.$claude, store.$codex)
            .sink { [weak self] _, _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
        updateStatusItem()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        store.refresh()
        launchAtLogin.refresh()
        let view = PopoverView(store: store, launchAtLogin: launchAtLogin)
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let remaining = store.overallRemaining
        let rendered = remaining.map { Int($0.rounded()) }
        if rendered != renderedRemaining || button.image == nil {
            renderedRemaining = rendered
            button.image = MenuBarGlyph.image(remaining: remaining)
            statusItem.length = NSStatusItem.variableLength
        }
        switch remaining {
        case .some(let value) where value < 12:
            button.contentTintColor = .systemRed
        case .some(let value) where value < 30:
            button.contentTintColor = .systemOrange
        default:
            button.contentTintColor = nil
        }
    }

}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}

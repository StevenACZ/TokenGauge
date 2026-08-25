import AppKit
import Combine
import SwiftUI
import TokenGaugeCore

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: UsageStore
    private let launchAtLogin: LaunchAtLoginManager
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?

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
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.image = ProviderLogoAssets.menuBarImage(for: .claude, size: 15)
            button.toolTip = "app.name".localized
        }

        Publishers.CombineLatest(store.$claude, store.$codex)
            .sink { [weak self] _, _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
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
        let window = store.menuBarWindow
        let remaining = window?.remainingPercentage
        let text = remaining.map { " \(Int($0.rounded()))%" } ?? " --"

        var color = NSColor.labelColor
        switch remaining {
        case .some(let value) where value < 12:
            color = .systemRed
        case .some(let value) where value < 30:
            color = .systemOrange
        default:
            break
        }
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = color.usingColorSpace(.sRGB) ?? color
        }

        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            ]
        )
        if let window {
            button.toolTip = "\(UsageFormatters.windowName(window)) · \(text.trimmingCharacters(in: .whitespaces))"
        }
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}

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
    private let windows: AppWindows
    private var cancellables = Set<AnyCancellable>()
    private var displayedProvider: UsageProvider?
    private var appearanceObservation: NSKeyValueObservation?
    private var outsideClickMonitor: Any?
    private var resignObserver: (any NSObjectProtocol)?

    init(store: UsageStore, launchAtLogin: LaunchAtLoginManager) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        windows = AppWindows(store: store, launchAtLogin: launchAtLogin)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "app.name".localized
        }

        Publishers.CombineLatest3(store.$claude, store.$codex, store.$primaryProvider)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
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
        let view = PopoverView(
            store: store,
            showSettings: { [weak self] in
                self?.dismissPopover()
                self?.windows.showSettings()
            },
            showAbout: { [weak self] in
                self?.dismissPopover()
                self?.windows.showAbout()
            })
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startDismissMonitors()
    }

    private func startDismissMonitors() {
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.dismissPopover() }
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.dismissPopover() }
            }
        }
    }

    private func stopDismissMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private func dismissPopover() {
        guard popover.isShown else {
            stopDismissMonitors()
            return
        }
        popover.performClose(nil)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if displayedProvider != store.primaryProvider {
            button.image = ProviderLogoAssets.menuBarImage(
                for: store.primaryProvider, size: Theme.Layout.menuBarIconSize)
            displayedProvider = store.primaryProvider
        }
        let providerName = "provider.\(store.primaryProvider.rawValue)".localized
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

        let title = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: Theme.Layout.menuBarFontSize, weight: .semibold),
            ]
        )
        if !button.attributedTitle.isEqual(to: title) {
            button.attributedTitle = title
        }
        if let window {
            button.toolTip =
                "\(providerName) · \(UsageFormatters.windowName(window)) · \(text.trimmingCharacters(in: .whitespaces))"
        } else {
            button.toolTip = "\(providerName) · \("status.unavailable".localized)"
        }
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        stopDismissMonitors()
        popover.contentViewController = nil
    }
}

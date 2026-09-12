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
    private var displayedPresentation: MenuBarPresentation?
    private var appearanceObservation: NSKeyValueObservation?
    private var popoverSizeObservation: NSKeyValueObservation?
    private var positioningUpdatePending = false
    private var positionedGeometry: PopoverGeometry?

    private struct PopoverGeometry: Equatable {
        let sourceWindow: NSRect
        let sourceButton: NSRect
        let contentSize: NSSize
    }
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
            button.postsFrameChangedNotifications = true
            NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: button)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.schedulePopoverPositionUpdate() }
                .store(in: &cancellables)
        }

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, let window = notification.object as? NSWindow,
                    window === self.statusItem.button?.window
                else { return }
                self.schedulePopoverPositionUpdate()
            }
            .store(in: &cancellables)

        popoverSizeObservation = popover.observe(\.contentSize, options: [.old, .new]) { [weak self] _, change in
            guard change.oldValue != change.newValue else { return }
            Task { @MainActor in self?.schedulePopoverPositionUpdate() }
        }

        Publishers.CombineLatest4(
            store.$claude, store.$codex, store.$displayMode, LocalizationManager.shared.$bundle
        )
        .receive(on: RunLoop.main)
        .combineLatest(
            store.$menuBarSize.receive(on: RunLoop.main), store.$claudeMenuBarSource.receive(on: RunLoop.main),
            store.$menuBarStyle.receive(on: RunLoop.main)
        )
        .sink { [weak self] _, _, _, _ in
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
                self?.showSettings()
            },
            showAbout: { [weak self] in
                self?.showAbout()
            })
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startDismissMonitors()
    }

    private func schedulePopoverPositionUpdate() {
        guard popover.isShown, !positioningUpdatePending else { return }
        positioningUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.positioningUpdatePending = false
            guard self.popover.isShown, let button = self.statusItem.button, let window = button.window else { return }
            let geometry = PopoverGeometry(
                sourceWindow: window.frame, sourceButton: button.frame, contentSize: self.popover.contentSize)
            guard geometry != self.positionedGeometry else { return }
            self.positionedGeometry = geometry
            self.popover.animates = false
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.popover.animates = true
        }
    }

    func showSettings() {
        dismissPopover()
        windows.showSettings()
    }

    func showAbout() {
        dismissPopover()
        windows.showAbout()
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
        let presentation = MenuBarPresentation(
            providers: store.displayMode.providers,
            state: { store.state(for: $0) },
            appearance: button.effectiveAppearance, size: store.menuBarSize, style: store.menuBarStyle,
            claudeSource: store.claudeMenuBarSource)
        guard presentation != displayedPresentation else { return }
        if displayedPresentation?.segments.first?.provider != presentation.segments.first?.provider
            || displayedPresentation?.size != presentation.size,
            let provider = presentation.segments.first?.provider
        {
            button.image = ProviderLogoAssets.menuBarImage(for: provider, size: presentation.size.iconSize)
        }
        button.attributedTitle = presentation.attributedTitle()
        button.toolTip = presentation.accessibilityLabel
        button.setAccessibilityLabel(presentation.accessibilityLabel)
        displayedPresentation = presentation
        schedulePopoverPositionUpdate()
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        positionedGeometry = nil
        stopDismissMonitors()
        popover.contentViewController = nil
    }
}

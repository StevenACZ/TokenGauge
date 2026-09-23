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
    private var history: HistoryDashboardModel?

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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
            store.$menuBarSize.receive(on: RunLoop.main), store.$claudeMenuBarWindows.receive(on: RunLoop.main),
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
        if let event = NSApp.currentEvent,
            event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        {
            showQuickMenu()
            return
        }
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
            }, history: historyModel())
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startDismissMonitors()
    }

    private func historyModel() -> HistoryDashboardModel {
        if let history { return history }
        let preview = store.historyReadsEnabled ? nil : [store.claude.snapshot, store.codex.snapshot].compactMap { $0 }
        let model = HistoryDashboardModel(previewSnapshots: preview, mode: store.historyMode)
        history = model
        return model
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
            claudeWindows: store.claudeMenuBarWindows)
        guard presentation != displayedPresentation else { return }
        if displayedPresentation?.segments.first?.provider != presentation.segments.first?.provider
            || displayedPresentation?.size != presentation.size
            || displayedPresentation?.style != presentation.style,
            let provider = presentation.segments.first?.provider
        {
            button.image =
                presentation.style == .rings
                ? nil : ProviderLogoAssets.menuBarImage(for: provider, size: presentation.size.iconSize)
        }
        button.attributedTitle = presentation.attributedTitle()
        button.toolTip = presentation.accessibilityLabel
        button.setAccessibilityLabel(presentation.accessibilityLabel)
        displayedPresentation = presentation
        schedulePopoverPositionUpdate()
    }
}

extension StatusItemController {
    private func showQuickMenu() {
        dismissPopover()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: "menu.quick.claude_windows".localized))
        let automatic = item("settings.claude_menu_bar.automatic".localized, #selector(selectAutomaticWindows))
        automatic.state = store.claudeMenuBarWindows.isEmpty ? .on : .off
        menu.addItem(automatic)
        for kind in ClaudeWindowKind.allCases {
            let entry = item(ClaudeWindowNames.name(kind, snapshot: store.claude.snapshot), #selector(toggleWindow))
            entry.representedObject = kind.rawValue
            entry.state = store.claudeMenuBarWindows.contains(kind) ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "settings.indicator_style".localized))
        for style in QuotaMenuBarStyle.allCases {
            let entry = item(style.titleKey.localized, #selector(selectMenuBarStyle))
            entry.representedObject = style.rawValue
            entry.state = store.menuBarStyle == style ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let privacy = item("settings.hide_account".localized, #selector(togglePrivacy))
        privacy.state = store.hideAccountLabel ? .on : .off
        menu.addItem(privacy)
        menu.addItem(item("action.refresh".localized, #selector(refreshNow)))
        menu.addItem(.separator())
        menu.addItem(item("settings.title".localized + "…", #selector(openSettings)))
        menu.addItem(item("action.quit".localized, #selector(quit)))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func selectAutomaticWindows() { store.claudeMenuBarWindows = [] }

    @objc private func toggleWindow(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = ClaudeWindowKind(rawValue: raw) else { return }
        store.toggleClaudeMenuBarWindow(kind)
    }

    @objc private func selectMenuBarStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = QuotaMenuBarStyle(rawValue: raw) else {
            return
        }
        store.menuBarStyle = style
    }

    @objc private func togglePrivacy() { store.hideAccountLabel.toggle() }
    @objc private func refreshNow() { store.refresh(force: true) }
    @objc private func openSettings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        positionedGeometry = nil
        stopDismissMonitors()
        popover.contentViewController = nil
        history?.popoverDidClose()
    }
}

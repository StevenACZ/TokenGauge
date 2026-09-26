import AppKit
import Combine
import SwiftUI
import TokenGaugeCore
import os

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
    private var previousApp: NSRunningApplication?
    private weak var trackingMenu: NSMenu?
    private var closeRequested = false
    private static let log = Logger(subsystem: "com.stevenacz.TokenGauge", category: "popover")

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
        popover.hasFullSizeContent = true
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

        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] notification in self?.trackingMenu = notification.object as? NSMenu }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] notification in
                guard let self, notification.object as? NSMenu === self.trackingMenu else { return }
                self.trackingMenu = nil
            }
            .store(in: &cancellables)

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
            store.$menuBarSize.receive(on: RunLoop.main),
            store.$claudeMenuBarWindows.combineLatest(store.$codexMenuBarWindows).receive(on: RunLoop.main),
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
            requestClose()
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
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front == NSRunningApplication.current ? nil : front
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startDismissMonitors()
    }

    private func historyModel() -> HistoryDashboardModel {
        if let history { return history }
        let preview = store.historyReadsEnabled ? nil : [store.claude.snapshot, store.codex.snapshot].compactMap { $0 }
        let model = HistoryDashboardModel(
            previewSnapshots: preview, mode: store.historyMode, historyURL: store.historyURL)
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
                let location = NSEvent.mouseLocation
                Task { @MainActor in
                    guard let self, self.trackingMenu == nil else { return }
                    guard self.popover.contentViewController?.view.window?.frame.contains(location) != true else {
                        Self.log.debug("outside monitor ignored a click inside the panel")
                        return
                    }
                    Self.log.debug("outside monitor closes")
                    self.dismissPopover()
                }
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    Self.log.debug("resign closes")
                    self?.dismissPopover()
                }
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
        requestClose()
    }

    private func requestClose() {
        closeRequested = true
        popover.performClose(nil)
        closeRequested = false
    }

    private func isPanelClick(_ event: NSEvent?) -> Bool {
        guard let event, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
            let panel = popover.contentViewController?.view.window
        else { return false }
        return event.window === panel
    }

    private func updateStatusItem() {
        guard let button = statusItem.button, !popover.isShown else { return }
        let presentation = MenuBarPresentation(
            providers: store.displayMode.providers,
            state: { store.state(for: $0) },
            appearance: button.effectiveAppearance, size: store.menuBarSize, style: store.menuBarStyle,
            selection: store.menuBarSelections)
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
    }
}

extension StatusItemController {
    private func showQuickMenu() {
        dismissPopover()
        let menu = NSMenu()
        menu.autoenablesItems = false
        for provider in [UsageProvider.codex, .claude] {
            addProviderSection(provider, to: menu)
        }
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

    private func addProviderSection(_ provider: UsageProvider, to menu: NSMenu) {
        let shown = store.isInMenuBar(provider)
        menu.addItem(.sectionHeader(title: "provider.\(provider.rawValue)".localized))
        let visibility = item("menu.quick.show_in_bar".localized, #selector(toggleProvider))
        visibility.representedObject = provider.rawValue
        visibility.state = shown ? .on : .off
        visibility.isEnabled = !shown || store.displayMode == .unified
        menu.addItem(visibility)
        let snapshot = store.state(for: provider).snapshot
        let kinds = ProviderStateResolver.menuBarKinds(snapshot: snapshot, provider: provider)
        guard kinds.count > 1 else {
            menu.addItem(.separator())
            return
        }
        let selection = store.menuBarSelection(for: provider)
        let automatic = item("settings.claude_menu_bar.automatic".localized, #selector(selectAutomaticWindows))
        automatic.representedObject = provider.rawValue
        automatic.state = selection.isEmpty ? .on : .off
        automatic.isEnabled = shown
        automatic.indentationLevel = 1
        menu.addItem(automatic)
        for kind in kinds {
            let entry = item(QuotaWindowNames.name(kind, snapshot: snapshot), #selector(toggleWindow))
            entry.representedObject = "\(provider.rawValue):\(kind.rawValue)"
            entry.state = selection.contains(kind) ? .on : .off
            entry.isEnabled = shown
            entry.indentationLevel = 1
            menu.addItem(entry)
        }
        menu.addItem(.separator())
    }

    @objc private func toggleProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = UsageProvider(rawValue: raw) else { return }
        store.setInMenuBar(!store.isInMenuBar(provider), provider: provider)
    }

    @objc private func selectAutomaticWindows(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = UsageProvider(rawValue: raw) else { return }
        store.setMenuBarSelection([], for: provider)
    }

    @objc private func toggleWindow(_ sender: NSMenuItem) {
        guard let parts = (sender.representedObject as? String)?.split(separator: ":").map(String.init),
            parts.count == 2, let provider = UsageProvider(rawValue: parts[0]),
            let kind = QuotaWindowKind(rawValue: parts[1])
        else { return }
        store.toggleMenuBarWindow(kind, for: provider)
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
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        let event = NSApp.currentEvent
        if !closeRequested, isPanelClick(event) {
            Self.log.debug("close refused: click inside panel")
            return false
        }
        guard trackingMenu != nil, let window = statusItem.button?.window else { return true }
        return event?.window !== window
    }
    func popoverWillClose(_ notification: Notification) {
        let event = NSApp.currentEvent
        Self.log.debug(
            "will close requested=\(self.closeRequested) event=\(event.map { String($0.type.rawValue) } ?? "none", privacy: .public) window=\(event?.window.map { String(describing: type(of: $0)) } ?? "none", privacy: .public)"
        )
        trackingMenu?.cancelTrackingWithoutAnimation()
    }
    func popoverDidClose(_ notification: Notification) {
        positionedGeometry = nil
        stopDismissMonitors()
        popover.contentViewController = nil
        history?.popoverDidClose()
        updateStatusItem()
        let previous = previousApp
        previousApp = nil
        if let previous, !previous.isTerminated, NSApp.isActive,
            !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain })
        {
            previous.activate(options: [])
        }
    }
}

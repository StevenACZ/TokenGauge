import AppKit
import SwiftUI
import TokenGaugeCore

struct HistoryCalendarView: NSViewRepresentable {
    let days: [HistoryCalendarDay]
    let providers: [UsageProvider]
    let selectedDayKey: String?
    let focusID: String
    var hoverEnabled = true
    var accent: Color = Color(nsColor: .labelColor)
    var resets: [HistoryReset] = []
    var pinnedDayKey: String?
    var pinSafeFrames: [CGRect] = []
    var onHoverCard: @MainActor (String?, HistoryDayCardAnchor?) -> Void = { _, _ in }
    var onPinCard: @MainActor (String, HistoryDayCardAnchor?) -> Void = { _, _ in }
    var onExitCalendar: @MainActor () -> Void = {}
    var onDismissCard: @MainActor () -> Void = {}
    let onSelect: @MainActor (String) -> Void

    func makeNSView(context: Context) -> HistoryCalendarScrollView {
        HistoryCalendarScrollView()
    }

    func updateNSView(_ view: HistoryCalendarScrollView, context: Context) {
        view.calendar.update(self)
        if view.focusID != focusID {
            view.focusID = focusID
            view.needsCenter = true
        }
        view.needsLayout = true
    }
}

final class HistoryCalendarScrollView: NSScrollView {
    let calendar = HistoryCalendarCanvas()
    var focusID: String?
    var needsCenter = true

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        automaticallyAdjustsContentInsets = false
        documentView = calendar
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = contentView.bounds.width
        guard width > 0 else { return }
        let oldPadding = calendar.sidePadding
        calendar.sidePadding = max(0, (width - 9) / 2)
        calendar.setFrameSize(
            NSSize(width: calendar.gridWidth + 2 * calendar.sidePadding, height: Theme.Layout.historyCalendarHeight))
        if needsCenter, let index = calendar.focusIndex {
            contentView.scroll(to: NSPoint(x: calendar.cellRect(index).midX - width / 2, y: 0))
            needsCenter = false
        } else if oldPadding != calendar.sidePadding {
            contentView.scroll(to: NSPoint(x: contentView.bounds.minX + calendar.sidePadding - oldPadding, y: 0))
        }
        reflectScrolledClipView(contentView)
    }

    override func scrollWheel(with event: NSEvent) {
        calendar.scrollDidMove()
        let delta =
            abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        let maximum = max(0, calendar.bounds.width - contentView.bounds.width)
        let x = min(maximum, max(0, contentView.bounds.minX - delta * scale))
        contentView.scroll(to: NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }
}

final class HistoryCalendarCanvas: NSView {
    private var days: [HistoryCalendarDay] = []
    private var providers: [UsageProvider] = []
    private var resets: [HistoryReset] = []
    private var resetsByDay: [String: [HistoryReset]] = [:]
    private var selected: String?
    private var pinned: String?
    private var hoverEnabled = true
    private var onSelect: (@MainActor (String) -> Void)?
    private var onHoverCard: (@MainActor (String?, HistoryDayCardAnchor?) -> Void)?
    private var onPinCard: (@MainActor (String, HistoryDayCardAnchor?) -> Void)?
    private var onExitCalendar: (@MainActor () -> Void)?
    private var onDismissCard: (@MainActor () -> Void)?
    private var hoverIndex: Int?
    private var hoverWork: DispatchWorkItem?
    private var pinSafeFrames: [CGRect] = []
    private var pinMonitor: Any?
    private var locale = Locale.current
    private var today = Calendar.current.startOfDay(for: Date())
    private var tracking: NSTrackingArea?
    private var lastMousePosition: NSPoint?
    private var elements: [HistoryCalendarAccessibilityDay] = []
    private var descriptions: [String] = []
    private var monthLayout = HistoryMonthLayout(days: [])
    private var months: [(HistoryMonthLayout.Section, String)] = []
    private var fills: [[NSColor]] = []
    private var minorities: [NSColor?] = []
    var sidePadding: CGFloat = 0 { didSet { if sidePadding != oldValue { needsDisplay = true } } }
    var gridWidth: CGFloat { max(9, monthLayout.gridWidth) }
    override var isFlipped: Bool { true }
    private var accentColor = Color(nsColor: .labelColor)
    private var accent: NSColor { NSColor(accentColor) }
    var focusIndex: Int? {
        days.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: today) }
            ?? days.lastIndex { $0.date <= today && $0.total(for: providers) != nil }
            ?? days.lastIndex { $0.date <= today }
    }

    deinit {
        MainActor.assumeIsolated {
            hoverWork?.cancel()
            if let pinMonitor { NSEvent.removeMonitor(pinMonitor) }
        }
    }

    func update(_ value: HistoryCalendarView) {
        onSelect = value.onSelect
        onHoverCard = value.onHoverCard
        onPinCard = value.onPinCard
        onExitCalendar = value.onExitCalendar
        onDismissCard = value.onDismissCard
        hoverEnabled = value.hoverEnabled
        pinned = value.pinnedDayKey
        pinSafeFrames = value.pinSafeFrames
        updatePinMonitor()
        let language = Locale(identifier: LocalizationManager.shared.language.rawValue)
        let newToday = Calendar.current.startOfDay(for: Date())
        let changed =
            providers != value.providers || locale != language || today != newToday
            || resets != value.resets
            || accentColor != value.accent
            || days.count != value.days.count
            || !zip(days, value.days).allSatisfy { $0.id == $1.id && $0.date == $1.date && $0.totals == $1.totals }
        let selectionChanged = selected != value.selectedDayKey
        selected = value.selectedDayKey
        guard changed || selectionChanged else { return }
        if changed {
            resets = value.resets
            resetsByDay = Dictionary(grouping: resets) { HistoryDashboardModel.dayKey($0.date) }
            days = value.days
            providers = value.providers
            accentColor = value.accent
            locale = language
            today = newToday
            monthLayout = HistoryMonthLayout(days: days)
            descriptions = days.map(description)
            months = monthLayout.sections.map {
                ($0, $0.date.formatted(.dateTime.month(.wide).locale(locale)).capitalized(with: locale))
            }
            let thresholds = HistoryIntensity.thresholds(totals: days.compactMap { $0.total(for: providers) })
            fills = days.map { day in
                let opacity = HistoryIntensity.opacity(total: day.total(for: providers) ?? 0, thresholds: thresholds)
                return day.dominantProviders(for: providers).map { provider in
                    color(provider).withAlphaComponent(opacity)
                }
            }
            minorities = days.map { day in
                let leaders = day.dominantProviders(for: providers)
                guard leaders.count == 1, let leader = leaders.first, let total = day.total(for: providers), total > 0,
                    let minority = providers.first(where: { $0 != leader }),
                    Double(day.tokens(for: minority) ?? 0) >= HistoryIntensity.minorityShare * Double(total)
                else { return nil }
                return color(minority).withAlphaComponent(
                    HistoryIntensity.opacity(total: total, thresholds: thresholds))
            }
            elements = days.indices.map { HistoryCalendarAccessibilityDay(canvas: self, index: $0) }
            setAccessibilityElement(false)
            setAccessibilityChildren(elements)
        }
        needsDisplay = true
    }

    func cellRect(_ index: Int) -> NSRect {
        monthLayout.cellRect(index).offsetBy(dx: sidePadding, dy: 0)
    }

    func cardAnchor(_ index: Int) -> HistoryDayCardAnchor? {
        guard let scroll = enclosingScrollView, let root = window?.contentView else { return nil }
        return HistoryDayCardAnchor(
            cell: localRect(convert(cellRect(index), to: scroll), in: scroll),
            bounds: localRect(scroll.convert(root.bounds, from: root), in: scroll))
    }

    private func localRect(_ rect: NSRect, in view: NSView) -> CGRect {
        view.isFlipped
            ? rect
            : CGRect(x: rect.minX, y: view.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func localPoint(_ locationInWindow: NSPoint, in view: NSView) -> CGPoint {
        let point = view.convert(locationInWindow, from: nil)
        return view.isFlipped ? point : CGPoint(x: point.x, y: view.bounds.height - point.y)
    }

    private func color(_ provider: UsageProvider) -> NSColor {
        NSColor(provider == .codex ? Theme.codex : Theme.claude)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (section, label) in months {
            let frame = NSRect(
                x: sidePadding + section.originX - 3, y: Theme.Layout.historyCalendarGridTop - 3,
                width: section.width + 6,
                height: Theme.Layout.historyCalendarHeight - Theme.Layout.historyCalendarGridTop + 1)
            if section.originX > 0 {
                let x = sidePadding + section.originX - Theme.Layout.historyMonthGap / 2
                let divider = NSBezierPath()
                divider.move(to: NSPoint(x: x, y: frame.minY + 4))
                divider.line(to: NSPoint(x: x, y: frame.maxY - 4))
                divider.lineWidth = 0.5
                NSColor.labelColor.withAlphaComponent(0.08).setStroke()
                divider.stroke()
            }
            NSColor.labelColor.withAlphaComponent(0.04).setFill()
            NSBezierPath(
                roundedRect: NSRect(
                    x: frame.minX + 1, y: Theme.Layout.historyCalendarGridTop + 58, width: frame.width - 2, height: 25),
                xRadius: 3, yRadius: 3
            ).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .medium),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.8),
            ]
            let labelWidth = (label as NSString).size(withAttributes: attributes).width
            (label as NSString).draw(
                at: NSPoint(x: sidePadding + section.originX + (section.width - labelWidth) / 2, y: 2),
                withAttributes: attributes)

        }
        for index in days.indices where cellRect(index).insetBy(dx: -2, dy: -2).intersects(dirtyRect) {
            let day = days[index]
            let rect = cellRect(index)
            let total = day.total(for: providers)
            let future = day.date > today
            let isToday = Calendar.current.isDate(day.date, inSameDayAs: today)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            if let total, !future {
                if total > 0, !fills[index].isEmpty {
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    let colors = fills[index]
                    for (part, color) in colors.enumerated() {
                        color.setFill()
                        NSRect(
                            x: rect.minX + CGFloat(part) * rect.width / CGFloat(colors.count), y: rect.minY,
                            width: rect.width / CGFloat(colors.count), height: rect.height
                        ).fill()
                    }
                    if let minority = minorities[index] {
                        minority.setFill()
                        let corner = NSBezierPath()
                        corner.move(to: NSPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.4))
                        corner.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
                        corner.line(to: NSPoint(x: rect.maxX - rect.width * 0.4, y: rect.maxY))
                        corner.close()
                        corner.fill()
                    }
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.08).setFill()
                    path.fill()
                }
            }
            if total == nil && !future {
                NSColor.secondaryLabelColor.withAlphaComponent(0.4).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            if day.id == selected {
                NSColor.labelColor.setStroke()
                let selection = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 3, yRadius: 3)
                selection.lineWidth = 1
                selection.stroke()
            }
            if isToday {
                accent.setStroke()
                path.lineWidth = 2
                path.stroke()
                NSColor.labelColor.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            }
            let resetProviders = providers.filter { provider in
                (resetsByDay[day.id] ?? []).contains { $0.provider == provider }
            }
            if !resetProviders.isEmpty {
                for (part, provider) in resetProviders.enumerated() {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(
                        rect: NSRect(
                            x: rect.minX - 1 + CGFloat(part) * (rect.width + 2) / CGFloat(resetProviders.count),
                            y: rect.minY - 1, width: (rect.width + 2) / CGFloat(resetProviders.count),
                            height: rect.height + 2)
                    ).addClip()
                    let projected = (resetsByDay[day.id] ?? []).filter { $0.provider == provider }.allSatisfy(
                        \.isProjected)
                    color(provider).withAlphaComponent(projected ? 0.55 : 1).setStroke()
                    path.lineWidth = projected ? 1.5 : 2
                    path.stroke()
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lastMousePosition = NSEvent.mouseLocation
        if window == nil { cancelHoverTimer() }
        updatePinMonitor()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    var trackingOptions: NSTrackingArea.Options { tracking?.options ?? [] }

    var hasPinMonitor: Bool { pinMonitor != nil }

    override func mouseMoved(with event: NSEvent) {
        let position = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        defer { lastMousePosition = position }
        guard hoverEnabled, position != lastMousePosition, pinned == nil else { return }
        guard let index = index(at: convert(event.locationInWindow, from: nil)) else {
            if hoverIndex != nil { cancelHoverCard() }
            return
        }
        scheduleHoverCard(index)
        select(index)
    }

    override func mouseExited(with event: NSEvent) {
        cancelHoverCard()
        guard pinned == nil else { return }
        onExitCalendar?()
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)), days.indices.contains(index),
            isEnabled(at: index)
        else {
            onDismissCard?()
            cancelHoverCard()
            return
        }
        cancelHoverCard()
        hoverIndex = index
        select(index)
        onPinCard?(days[index].id, cardAnchor(index))
    }

    func scrollDidMove() {
        onDismissCard?()
        cancelHoverCard()
    }

    private func updatePinMonitor() {
        guard pinned != nil, window != nil else {
            if let pinMonitor { NSEvent.removeMonitor(pinMonitor) }
            pinMonitor = nil
            if let window, window.firstResponder === self { window.makeFirstResponder(window.contentView) }
            return
        }
        if pinMonitor == nil {
            pinMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.passesPinnedEvent(event) ?? true } ? event : nil
            }
        }
        if let window, window.firstResponder !== self { window.makeFirstResponder(self) }
    }

    override var acceptsFirstResponder: Bool { pinned != nil }

    override func cancelOperation(_ sender: Any?) {
        guard pinned != nil else {
            nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender)
            return
        }
        dismissPinnedCard()
    }

    private func dismissPinnedCard() {
        pinned = nil
        updatePinMonitor()
        onDismissCard?()
    }

    func passesPinnedEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyDown {
            guard event.keyCode == 53 else { return true }
            dismissPinnedCard()
            return false
        }
        if event.window === window, let scroll = enclosingScrollView {
            let point = localPoint(event.locationInWindow, in: scroll)
            if scroll.bounds.contains(point) || pinSafeFrames.contains(where: { $0.contains(point) }) {
                return true
            }
        }
        onDismissCard?()
        return true
    }

    private func scheduleHoverCard(_ index: Int) {
        guard hoverIndex != index else { return }
        cancelHoverCard()
        hoverIndex = index
        guard days.indices.contains(index), isEnabled(at: index) else { return }
        let key = days[index].id
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hoverIndex == index else { return }
                self.onHoverCard?(key, self.cardAnchor(index))
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func cancelHoverTimer() {
        hoverWork?.cancel()
        hoverWork = nil
        hoverIndex = nil
    }

    private func cancelHoverCard() {
        cancelHoverTimer()
        onHoverCard?(nil, nil)
    }

    private func index(at point: NSPoint) -> Int? {
        monthLayout.index(at: NSPoint(x: point.x - sidePadding, y: point.y))
    }

    func select(_ index: Int) {
        guard days.indices.contains(index), isEnabled(at: index), days[index].id != selected else { return }
        onSelect?(days[index].id)
    }

    private func description(_ day: HistoryCalendarDay) -> String {
        let prefix = Calendar.current.isDate(day.date, inSameDayAs: today) ? "history.today".localized + " · " : ""
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale))
        let totals = providers.map { provider in
            (provider == .claude ? "provider.claude_short" : "provider.codex").localized + " "
                + (day.tokens(for: provider).map { $0.formatted(.number.locale(locale)) } ?? "history.unknown".localized)
        }.joined(separator: " · ")
        let leaders = day.dominantProviders(for: providers)
        let usage: String
        if providers.count > 1, leaders.count == 1, let leader = leaders.first {
            usage =
                "\n"
                + "history.dominant".localized(
                    (leader == .claude ? "provider.claude_short" : "provider.codex").localized)
        } else if leaders.count > 1 {
            usage = "\n" + "history.equal_use".localized
        } else {
            usage = ""
        }
        let resetText = (resetsByDay[day.id] ?? [])
            .map {
                "history.weekly_reset".localized + " · " + $0.label
                    + ($0.isProjected ? " · " + "history.projected".localized : "")
            }.joined(separator: "\n")
        return prefix + date + ": " + totals + usage + (resetText.isEmpty ? "" : "\n" + resetText)
    }

    func accessibilityLabel(at index: Int) -> String { descriptions.indices.contains(index) ? descriptions[index] : "" }
    func isEnabled(at index: Int) -> Bool {
        days.indices.contains(index) && (days[index].date <= today || resetsByDay[days[index].id] != nil)
    }
    func isSelected(at index: Int) -> Bool { days.indices.contains(index) && days[index].id == selected }
}

private final class HistoryCalendarAccessibilityDay: NSAccessibilityElement {
    weak var canvas: HistoryCalendarCanvas?
    let index: Int

    init(canvas: HistoryCalendarCanvas, index: Int) {
        self.canvas = canvas
        self.index = index
        super.init()
        setAccessibilityParent(canvas)
        setAccessibilityRole(.button)
    }

    override func accessibilityLabel() -> String? {
        MainActor.assumeIsolated { [canvas, index] in canvas?.accessibilityLabel(at: index) }
    }
    override func isAccessibilityEnabled() -> Bool {
        MainActor.assumeIsolated { [canvas, index] in canvas?.isEnabled(at: index) ?? false }
    }
    override func isAccessibilitySelected() -> Bool {
        MainActor.assumeIsolated { [canvas, index] in canvas?.isSelected(at: index) ?? false }
    }
    override func accessibilityFrame() -> NSRect {
        MainActor.assumeIsolated { [canvas, index] in
            guard let canvas, let window = canvas.window else { return .zero }
            return window.convertToScreen(canvas.convert(canvas.cellRect(index), to: nil))
        }
    }
    override func accessibilityPerformPress() -> Bool {
        MainActor.assumeIsolated { [canvas, index] in
            guard let canvas, canvas.isEnabled(at: index) else { return false }
            canvas.scrollToVisible(canvas.cellRect(index))
            canvas.select(index)
            return true
        }
    }
}

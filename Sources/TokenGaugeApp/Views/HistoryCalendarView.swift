import AppKit
import SwiftUI
import TokenGaugeCore

struct HistoryCalendarView: NSViewRepresentable {
    let days: [HistoryCalendarDay]
    let providers: [UsageProvider]
    let selectedDayKey: String?
    let focusID: String
    var hoverEnabled = true
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
        calendar.setFrameSize(NSSize(width: calendar.gridWidth + 2 * calendar.sidePadding, height: 96))
        if needsCenter, let index = calendar.focusIndex {
            contentView.scroll(to: NSPoint(x: calendar.cellRect(index).midX - width / 2, y: 0))
            needsCenter = false
        } else if oldPadding != calendar.sidePadding {
            contentView.scroll(to: NSPoint(x: contentView.bounds.minX + calendar.sidePadding - oldPadding, y: 0))
        }
        calendar.updateTooltips()
        reflectScrolledClipView(contentView)
    }

    override func scrollWheel(with event: NSEvent) {
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
    private var selected: String?
    private var hoverEnabled = true
    private var onSelect: (@MainActor (String) -> Void)?
    private var locale = Locale.current
    private var today = Calendar.current.startOfDay(for: Date())
    private var maximum = 1
    private var tracking: NSTrackingArea?
    private var lastMousePosition: NSPoint?
    private var elements: [HistoryCalendarAccessibilityDay] = []
    private var descriptions: [String] = []
    private var months: [(Int, String)] = []
    var sidePadding: CGFloat = 0 { didSet { if sidePadding != oldValue { tooltipsDirty = true; needsDisplay = true } } }
    private var tooltipsDirty = true
    private var leadingDays = 0
    var gridWidth: CGFloat { max(9, CGFloat((leadingDays + days.count + 6) / 7) * 12 - 3) }
    override var isFlipped: Bool { true }
    private var accent: NSColor { NSColor(providers == [.claude] ? Theme.claude : Theme.codex) }
    var focusIndex: Int? {
        days.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: today) }
            ?? days.lastIndex { $0.date <= today && $0.total(for: providers) != nil }
            ?? days.lastIndex { $0.date <= today }
    }

    func update(_ value: HistoryCalendarView) {
        onSelect = value.onSelect
        hoverEnabled = value.hoverEnabled
        let language = Locale(identifier: LocalizationManager.shared.language.rawValue)
        let newToday = Calendar.current.startOfDay(for: Date())
        let changed =
            providers != value.providers || locale != language || today != newToday
            || days.count != value.days.count
            || !zip(days, value.days).allSatisfy { $0.id == $1.id && $0.date == $1.date && $0.totals == $1.totals }
        let selectionChanged = selected != value.selectedDayKey
        selected = value.selectedDayKey
        guard changed || selectionChanged else { return }
        if changed {
            days = value.days
            providers = value.providers
            locale = language
            today = newToday
            maximum = max(1, days.compactMap { $0.total(for: providers) }.max() ?? 0)
            leadingDays = days.first.map { (Calendar.current.component(.weekday, from: $0.date) + 5) % 7 } ?? 0
            descriptions = days.map(description)
            months = days.indices.compactMap { index in
                guard Calendar.current.component(.day, from: days[index].date) == 1 else { return nil }
                return (
                    (index + leadingDays) / 7, days[index].date.formatted(.dateTime.month(.abbreviated).locale(locale))
                )
            }
            elements = days.indices.map { HistoryCalendarAccessibilityDay(canvas: self, index: $0) }
            setAccessibilityElement(false)
            setAccessibilityChildren(elements)
            tooltipsDirty = true
        }
        needsDisplay = true
    }

    func cellRect(_ index: Int) -> NSRect {
        let position = index + leadingDays
        return NSRect(
            x: sidePadding + CGFloat(position / 7) * 12, y: 15 + CGFloat(position % 7) * 12, width: 9, height: 9)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (week, label) in months {
            (label as NSString).draw(
                at: NSPoint(x: sidePadding + CGFloat(week) * 12, y: 2),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.secondaryLabelColor,
                ])
        }
        for index in days.indices where cellRect(index).insetBy(dx: -1, dy: -1).intersects(dirtyRect) {
            let day = days[index]
            let rect = cellRect(index)
            let total = day.total(for: providers)
            let future = day.date > today
            let isToday = Calendar.current.isDate(day.date, inSameDayAs: today)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            if let total, !future {
                (total > 0
                    ? accent.withAlphaComponent(0.25 + 0.75 * Double(total) / Double(maximum))
                    : NSColor.labelColor.withAlphaComponent(0.08)).setFill()
                path.fill()
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
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lastMousePosition = NSEvent.mouseLocation
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let position = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        defer { lastMousePosition = position }
        guard hoverEnabled, position != lastMousePosition,
            let index = index(at: convert(event.locationInWindow, from: nil))
        else { return }
        select(index)
    }

    override func mouseDown(with event: NSEvent) {
        if let index = index(at: convert(event.locationInWindow, from: nil)) { select(index) }
    }

    private func index(at point: NSPoint) -> Int? {
        guard point.x >= sidePadding, point.y >= 15 else { return nil }
        let column = Int((point.x - sidePadding) / 12)
        let row = Int((point.y - 15) / 12)
        let index = column * 7 + row - leadingDays
        guard row < 7, days.indices.contains(index), cellRect(index).contains(point) else { return nil }
        return index
    }

    func select(_ index: Int) {
        guard days.indices.contains(index), days[index].date <= today, days[index].id != selected else { return }
        onSelect?(days[index].id)
    }

    @objc func view(
        _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?
    ) -> String {
        index(at: point).map { descriptions[$0] } ?? ""
    }

    func updateTooltips() {
        guard tooltipsDirty else { return }
        removeAllToolTips()
        for index in days.indices { addToolTip(cellRect(index), owner: self, userData: nil) }
        tooltipsDirty = false
    }

    private func description(_ day: HistoryCalendarDay) -> String {
        let prefix = Calendar.current.isDate(day.date, inSameDayAs: today) ? "history.today".localized + " · " : ""
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale))
        let totals = providers.map { provider in
            (provider == .claude ? "provider.claude_short" : "provider.codex").localized + " "
                + (day.tokens(for: provider).map { $0.formatted(.number.locale(locale)) } ?? "history.unknown".localized)
        }.joined(separator: " · ")
        return prefix + date + ": " + totals
    }

    func accessibilityLabel(at index: Int) -> String { descriptions.indices.contains(index) ? descriptions[index] : "" }
    func isEnabled(at index: Int) -> Bool { days.indices.contains(index) && days[index].date <= today }
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

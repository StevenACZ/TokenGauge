import AppKit
import SwiftUI

@MainActor
enum HistoryControlAppearance {
    static func apply(to control: NSSegmentedControl) {
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.font = .systemFont(ofSize: 10)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

struct HistoryPeriodControl: NSViewRepresentable {
    let title: String
    let titleWidth: CGFloat
    let canGoBack: Bool
    let canGoForward: Bool
    let onPrevious: () -> Void
    let onToday: () -> Void
    let onNext: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ["", title, ""], trackingMode: .momentary,
            target: context.coordinator, action: #selector(Coordinator.select(_:)))
        HistoryControlAppearance.apply(to: control)
        control.segmentDistribution = .fill
        control.setWidth(22, forSegment: 0)
        control.setWidth(titleWidth, forSegment: 1)
        control.setWidth(22, forSegment: 2)
        for (index, symbol, key) in [(0, "chevron.left", "history.previous"), (2, "chevron.right", "history.next")] {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: key.localized)
            image?.size = NSSize(width: 8, height: 10)
            control.setImage(image, forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            control.setToolTip(key.localized, forSegment: index)
        }
        control.setToolTip("history.return_today".localized, forSegment: 1)
        control.setAccessibilityIdentifier("TokenGauge.historyPeriod.control")
        control.setAccessibilityLabel("history.period".localized)
        update(control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        update(control)
    }

    private func update(_ control: NSSegmentedControl) {
        if control.label(forSegment: 1) != title { control.setLabel(title, forSegment: 1) }
        if control.width(forSegment: 1) != titleWidth { control.setWidth(titleWidth, forSegment: 1) }
        control.setEnabled(canGoBack, forSegment: 0)
        control.setEnabled(canGoForward, forSegment: 2)
    }

    @MainActor final class Coordinator: NSObject {
        var parent: HistoryPeriodControl
        init(_ parent: HistoryPeriodControl) { self.parent = parent }

        @objc func select(_ control: NSSegmentedControl) {
            switch control.selectedSegment {
            case 0: if parent.canGoBack { parent.onPrevious() }
            case 1: parent.onToday()
            case 2: if parent.canGoForward { parent.onNext() }
            default: break
            }
        }
    }
}

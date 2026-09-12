import AppKit
import SwiftUI

struct HistoryModeControl: NSViewRepresentable {
    @Binding var mode: HistoryMode

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: HistoryMode.allCases.map { $0.titleKey.localized },
            trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.select(_:)))
        control.segmentStyle = .rounded
        control.segmentDistribution = .fillEqually
        control.controlSize = .small
        control.font = .systemFont(ofSize: 10)
        control.selectedSegment = HistoryMode.allCases.firstIndex(of: mode) ?? 0
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setAccessibilityIdentifier("TokenGauge.historyMode.control")
        control.setAccessibilityLabel("history.view".localized)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        for (index, item) in HistoryMode.allCases.enumerated() {
            let label = item.titleKey.localized
            if control.label(forSegment: index) != label { control.setLabel(label, forSegment: index) }
        }
        let selected = HistoryMode.allCases.firstIndex(of: mode) ?? 0
        if control.selectedSegment != selected { control.selectedSegment = selected }
    }

    @MainActor final class Coordinator: NSObject {
        var parent: HistoryModeControl
        init(_ parent: HistoryModeControl) { self.parent = parent }

        @objc func select(_ control: NSSegmentedControl) {
            guard HistoryMode.allCases.indices.contains(control.selectedSegment) else { return }
            parent.mode = HistoryMode.allCases[control.selectedSegment]
        }
    }
}

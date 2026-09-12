import SwiftUI
import TokenGaugeCore

struct CompactQuotaWindowRow: View {
    let window: QuotaWindow
    let tint: Color
    let chips: [ModelUsageChip]
    var historical = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(UsageFormatters.windowName(window))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .help(UsageFormatters.windowHelp(window))
                GaugeBar(
                    fraction: window.remainingPercentage / 100,
                    tint: Theme.severity(remaining: window.remainingPercentage) ?? tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(UsageFormatters.percentage(window.remainingPercentage))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.severity(remaining: window.remainingPercentage) ?? .primary)
                    Text((historical ? "quota.last_remaining" : "quota.remaining").localized)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Text(UsageFormatters.reset(window.resetsAt))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .help(
            [UsageFormatters.windowHelp(window), UsageFormatters.modelChips(chips)].compactMap { $0 }.joined(
                separator: "\n")
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(UsageFormatters.modelChips(chips) ?? "")
    }
}

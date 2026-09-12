import SwiftUI
import TokenGaugeCore

struct QuotaWindowRow: View {
    let window: QuotaWindow
    let tint: Color
    let chips: [ModelUsageChip]
    let prominent: Bool
    var historical = false
    var showPace = false
    var pace: QuotaPace?

    private var valueColor: Color {
        Theme.severity(remaining: window.remainingPercentage) ?? .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(UsageFormatters.windowName(window))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .help(UsageFormatters.windowHelp(window))
                if window.id.hasPrefix("base_model_inference.") || window.displayName?.lowercased() == "gpt-reserve" {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .help(UsageFormatters.windowHelp(window))
                        .accessibilityLabel(UsageFormatters.windowHelp(window))
                }
                Spacer(minLength: 4)
                Text(UsageFormatters.percentage(window.remainingPercentage))
                    .font(.system(size: prominent ? 25 : 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                Text((historical ? "quota.last_remaining" : "quota.remaining").localized)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            GaugeBar(
                fraction: window.remainingPercentage / 100,
                tint: prominent ? (Theme.severity(remaining: window.remainingPercentage) ?? tint) : tint.opacity(0.65))

            HStack(spacing: 6) {
                Text(UsageFormatters.reset(window.resetsAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let summary = UsageFormatters.modelChips(chips) {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .monospacedDigit()
                        .layoutPriority(-1)
                }
            }
            if showPace { QuotaPaceLabel(pace: pace) }
        }
    }
}

import SwiftUI
import TokenGaugeCore

struct QuotaRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quotaAnimationsEnabled) private var animateChanges
    let remainingPercentage: Double
    let tint: Color
    var historical = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: Theme.Layout.quotaRingLineWidth)
            Circle()
                .trim(from: 0, to: min(max(remainingPercentage / 100, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: Theme.Layout.quotaRingLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animateChanges && !reduceMotion ? Theme.Motion.value : nil, value: remainingPercentage)
            VStack(spacing: 1) {
                Text(UsageFormatters.percentage(remainingPercentage))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.severity(remaining: remainingPercentage) ?? .primary)
                Text((historical ? "quota.last_remaining" : "quota.remaining").localized)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(5)
        }
        .padding(Theme.Layout.quotaRingLineWidth / 2)
        .frame(width: Theme.Layout.quotaRingDiameter, height: Theme.Layout.quotaRingDiameter)
        .accessibilityElement(children: .combine)
    }
}

struct QuotaRingWindow: View {
    let window: QuotaWindow
    let tint: Color
    let chips: [ModelUsageChip]
    var historical = false
    var showPace = false
    var pace: QuotaPace?

    var body: some View {
        VStack(spacing: 4) {
            Text(UsageFormatters.windowName(window))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 26, alignment: .bottom)
                .help(UsageFormatters.windowHelp(window))
            QuotaRing(
                remainingPercentage: window.remainingPercentage,
                tint: Theme.severity(remaining: window.remainingPercentage) ?? tint,
                historical: historical)
            Text(UsageFormatters.reset(window.resetsAt))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showPace { QuotaPaceLabel(pace: pace) }
            if let summary = UsageFormatters.modelChips(chips) {
                Text(summary)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(summary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }
}

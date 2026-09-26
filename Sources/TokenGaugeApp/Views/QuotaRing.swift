import SwiftUI
import TokenGaugeCore

struct QuotaRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quotaAnimationsEnabled) private var animateChanges
    let remainingPercentage: Double
    let tint: Color
    var historical = false
    var metrics: QuotaRingMetrics = .grid

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: metrics.lineWidth)
            Circle()
                .trim(from: 0, to: min(max(remainingPercentage / 100, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: metrics.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animateChanges && !reduceMotion ? Theme.Motion.value : nil, value: remainingPercentage)
            VStack(spacing: 1) {
                Text(UsageFormatters.percentage(remainingPercentage))
                    .font(.system(size: metrics.percentageSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.severity(remaining: remainingPercentage) ?? .primary)
                    .quotaValueTransition(remainingPercentage)
                if metrics.showsLabel {
                    Text((historical ? "quota.last_remaining" : "quota.remaining").localized)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(metrics.contentPadding)
        }
        .padding(metrics.lineWidth / 2)
        .frame(width: metrics.diameter, height: metrics.diameter)
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
    var previousPace: QuotaPace?
    var session: QuotaForecast?
    var metrics: QuotaRingMetrics = .grid
    var alignsTitleRows = true

    var body: some View {
        VStack(spacing: Theme.Layout.ringSectionSpacing) {
            Text(UsageFormatters.windowName(window))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: alignsTitleRows ? Theme.Layout.ringTitleHeight : nil, alignment: .bottom)
                .help(UsageFormatters.windowHelp(window))
            QuotaRing(
                remainingPercentage: window.remainingPercentage,
                tint: Theme.severity(remaining: window.remainingPercentage) ?? tint,
                historical: historical,
                metrics: metrics)
            VStack(spacing: 4) {
                Text(UsageFormatters.reset(window.resetsAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                if showPace { QuotaPaceLabel(pace: pace, previousPace: previousPace) }
                if let session { SessionForecastLabel(forecast: session) }
                if let summary = UsageFormatters.modelChips(chips) {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        .help(summary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: showPace || session != nil ? .contain : .combine)
    }
}

struct QuotaRingRow: View {
    let window: QuotaWindow
    let tint: Color
    let chips: [ModelUsageChip]
    var historical = false
    var showPace = false
    var pace: QuotaPace?
    var previousPace: QuotaPace?
    var session: QuotaForecast?

    var body: some View {
        HStack(spacing: Theme.Layout.quotaRingSpacing) {
            QuotaRing(
                remainingPercentage: window.remainingPercentage,
                tint: Theme.severity(remaining: window.remainingPercentage) ?? tint,
                historical: historical,
                metrics: .row)
            VStack(alignment: .leading, spacing: 3) {
                Text(UsageFormatters.windowName(window))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .help(UsageFormatters.windowHelp(window))
                Text(
                    (historical ? "quota.last_remaining_value" : "quota.remaining_value").localized(
                        UsageFormatters.percentage(window.remainingPercentage))
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()
                Text(UsageFormatters.reset(window.resetsAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showPace { QuotaPaceLabel(pace: pace, previousPace: previousPace) }
                if let session { SessionForecastLabel(forecast: session) }
                ModelChipsLabel(chips: chips)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: showPace || session != nil ? .contain : .combine)
    }
}

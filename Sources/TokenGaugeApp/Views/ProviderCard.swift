import SwiftUI
import TokenGaugeCore

struct ProviderCard: View {
    let provider: UsageProvider
    let state: ProviderViewState

    private var tint: Color {
        provider == .claude ? Theme.claude : Theme.codex
    }

    private var visibleWindows: [QuotaWindow] {
        guard let snapshot = state.snapshot else { return [] }
        return WindowVisibility.visible(snapshot.windows, provider: provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if visibleWindows.isEmpty {
                statusMessage
            } else {
                ForEach(visibleWindows) { window in
                    QuotaWindowRow(
                        window: window,
                        tint: tint,
                        chips: chips(for: window)
                    )
                }
            }
        }
        .padding(10)
        .providerCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            ProviderLogo(provider: provider, size: 14)
                .frame(width: 21, height: 21)
                .background(Circle().fill(tint.opacity(0.13)))

            Text(provider == .claude ? "provider.claude".localized : "provider.codex".localized)
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 4)

            if let credits = state.snapshot?.availableResetCredits, credits > 0 {
                Text(UsageFormatters.resetCredits(credits))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint.opacity(0.13)))
            }

            if state.isRefreshing {
                ProgressView().controlSize(.mini)
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(statusSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chips(for window: QuotaWindow) -> [ModelUsageChip] {
        guard provider == .claude, let snapshot = state.snapshot else { return [] }
        return ModelActivity.chips(buckets: snapshot.modelBuckets, since: window.startsAt, limit: 2)
    }

    @ViewBuilder
    private var statusMessage: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: statusIcon)
                .font(.system(size: 11))
                .foregroundStyle(statusColor)
            Text(messageText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

    private var statusText: String {
        switch state.status {
        case .loading: return "status.loading".localized
        case .ready: return "status.live".localized
        case .waiting: return "status.waiting".localized
        case .stale: return "status.stale".localized
        case .unavailable: return "status.unavailable".localized
        }
    }

    private var statusSubtitle: String {
        guard state.status == .ready, let capturedAt = state.snapshot?.capturedAt else { return statusText }
        return UsageFormatters.lastUpdated(capturedAt)
    }

    private var statusIcon: String {
        switch state.status {
        case .loading: return "clock"
        case .ready: return "checkmark.circle.fill"
        case .waiting: return "ellipsis.circle"
        case .stale: return "clock.badge.exclamationmark"
        case .unavailable: return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .ready: return .green
        case .stale: return .orange
        case .unavailable: return .red
        case .loading, .waiting: return .secondary
        }
    }

    private var messageText: String {
        switch state.status {
        case .loading:
            return "message.loading".localized
        case .waiting where provider == .claude:
            return "message.claude_waiting".localized
        case .waiting:
            return "message.waiting".localized
        case .stale:
            return "message.stale".localized
        case .unavailable where provider == .codex:
            return "message.codex_unavailable".localized
        case .unavailable:
            return "message.claude_unavailable".localized
        case .ready:
            return "message.ready".localized
        }
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindow
    let tint: Color
    let chips: [ModelUsageChip]

    private var valueColor: Color {
        Theme.severity(remaining: window.remainingPercentage) ?? .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(UsageFormatters.windowName(window))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(UsageFormatters.percentage(window.remainingPercentage))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .contentTransition(.numericText())
                Text("quota.remaining".localized)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            GaugeBar(fraction: window.remainingPercentage / 100, tint: tint)

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
        }
    }
}

import SwiftUI
import TokenGaugeCore

struct ProviderCard: View {
    let provider: UsageProvider
    let state: ProviderViewState

    private var tint: Color {
        provider == .claude ? Theme.claude : Theme.codex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let snapshot = state.snapshot {
                if snapshot.windows.isEmpty {
                    statusMessage
                } else {
                    ForEach(snapshot.windows) { window in
                        QuotaWindowRow(window: window, tint: tint)
                    }
                }
            } else {
                statusMessage
            }
        }
        .padding(12)
        .providerCard(tint: tint)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: provider == .claude ? "sparkles" : "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 29, height: 29)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 0) {
                Text(provider == .claude ? "provider.claude".localized : "provider.codex".localized)
                    .font(.headline)
                Text(statusSubtitle)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            if let snapshot = state.snapshot {
                HStack(spacing: 7) {
                    if let count = snapshot.availableResetCredits, count > 0 {
                        Label("\(count)", systemImage: "arrow.counterclockwise.circle.fill")
                    }
                    if let balance = snapshot.creditBalance {
                        Text("credits.compact".localized(balance))
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
            }
            if state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(messageText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
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
        guard let capturedAt = state.snapshot?.capturedAt else { return statusText }
        return "\(statusText) · \(UsageFormatters.lastUpdated(capturedAt))"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(UsageFormatters.windowName(window))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(
                        "quota.used_with_reset".localized(
                            UsageFormatters.percentage(window.usedPercentage),
                            UsageFormatters.reset(window.resetsAt)
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
                Text(UsageFormatters.percentage(window.remainingPercentage))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            ProgressView(value: window.remainingPercentage, total: 100)
                .tint(tint)
                .animation(Theme.Motion.value, value: window.remainingPercentage)
        }
    }
}

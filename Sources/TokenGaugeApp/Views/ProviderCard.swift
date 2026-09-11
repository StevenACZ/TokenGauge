import SwiftUI
import TokenGaugeCore

struct ProviderCard: View {
    let provider: UsageProvider
    let state: ProviderViewState
    var compact = false
    var showProviderTitle = false
    var showLunaReserve = true
    var hiddenClaudeWindows: Set<ClaudeWindowKind> = []
    var claudeMenuBarSource: ClaudeMenuBarSource = .automatic

    private var tint: Color {
        provider == .claude ? Theme.claude : Theme.codex
    }

    private var visibleWindows: [QuotaWindow] {
        guard state.status == .ready, let snapshot = state.snapshot else { return [] }
        return WindowVisibility.visible(
            snapshot.windows, provider: provider, showLunaReserve: showLunaReserve,
            hiddenClaudeWindows: hiddenClaudeWindows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if compact {
                compactHeader
            } else {
                header
                if visibleWindows.isEmpty {
                    statusMessage
                    if let capturedAt = state.snapshot?.capturedAt {
                        Text("updated.last_known".localized(UsageFormatters.lastUpdated(capturedAt)))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(visibleWindows.enumerated()), id: \.element.id) { index, window in
                        if index > 0 { Divider() }
                        QuotaWindowRow(
                            window: window,
                            tint: tint,
                            chips: chips(for: window),
                            prominent: index == 0
                        )
                    }
                }
            }
        }
        .padding(compact ? 9 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .providerCard()
    }

    private var compactHeader: some View {
        HStack(spacing: 7) {
            ProviderLogo(provider: provider, size: 13)
            Text(provider == .claude ? "provider.claude".localized : "provider.codex".localized)
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 4)
            Text(compactStatus)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var compactStatus: String {
        guard state.status == .ready else { return statusText }
        guard let window = ProviderStateResolver.menuBarWindow(state: state, claudeSource: claudeMenuBarSource)
        else { return statusText }
        return "quota.remaining_value".localized(UsageFormatters.percentage(window.remainingPercentage))
    }

    private var header: some View {
        HStack(spacing: 5) {
            if showProviderTitle {
                ProviderLogo(provider: provider, size: 13)
                Text("provider.\(provider.rawValue)".localized).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 4)
            }
            Circle().fill(statusColor).frame(width: 5, height: 5)
            Text(statusSubtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if !showProviderTitle { Spacer(minLength: 4) }
            if state.status == .ready, let credits = state.snapshot?.availableResetCredits, credits > 0 {
                Text(UsageFormatters.resetCredits(credits))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
            }
        }
    }

    private var scopedFamilies: Set<String> {
        Set(
            visibleWindows.compactMap { window in
                guard let name = window.displayName, !name.isEmpty else { return nil }
                return name.lowercased()
            }
        )
    }

    private func chips(for window: QuotaWindow) -> [ModelUsageChip] {
        guard provider == .claude, let snapshot = state.snapshot else { return [] }
        let isAggregateWeekly = window.durationMinutes == 10_080 && (window.displayName ?? "").isEmpty
        return ModelActivity.chips(
            buckets: snapshot.modelBuckets,
            since: window.startsAt,
            limit: 2,
            family: window.displayName,
            excludingFamilies: isAggregateWeekly ? scopedFamilies : []
        )
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
        .help(state.snapshot?.capturedAt.map { "updated.last_known".localized(UsageFormatters.lastUpdated($0)) } ?? "")
    }

    private var statusText: String {
        switch state.status {
        case .loading: return "status.loading".localized
        case .ready: return "status.live".localized
        case .waiting: return "status.waiting".localized
        case .stale: return "status.stale".localized
        case .unavailable: return "status.unavailable".localized
        case .authenticationRequired: return "status.authentication_required".localized
        case .accessDenied: return "status.access_denied".localized
        case .cancelled: return "status.cancelled".localized
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
        case .authenticationRequired: return "person.crop.circle.badge.exclamationmark"
        case .accessDenied: return "lock"
        case .cancelled: return "pause.circle"
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .ready: return .green
        case .stale: return .orange
        case .unavailable, .accessDenied: return .red
        case .authenticationRequired: return .orange
        case .loading, .waiting, .cancelled: return .secondary
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
        case .authenticationRequired:
            return "message.authentication_required".localized
        case .accessDenied:
            return "message.access_denied".localized
        case .cancelled:
            return "message.cancelled".localized
        case .ready:
            return "message.ready".localized
        }
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindow
    let tint: Color
    let chips: [ModelUsageChip]
    let prominent: Bool

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
                Text("quota.remaining".localized)
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
        }
    }
}

import SwiftUI
import TokenGaugeCore

struct ProviderCard: View {
    let provider: UsageProvider
    let state: ProviderViewState
    var compact = false
    var panelStyle: QuotaPanelStyle = .standard
    var showProviderTitle = false
    var showLunaReserve = true
    var hiddenClaudeWindows: Set<QuotaWindowKind> = []
    var menuBarWindows: Set<QuotaWindowKind> = []
    var hidesAccountLabel = false
    var claudeAutomaticRecovery = false
    var showHourlyPace = false
    var stretchesHeight = false
    var accountLabel: String?
    var paces: [String: QuotaPace] = [:]
    var previousPaces: [String: QuotaPace] = [:]

    private var tint: Color {
        provider == .claude ? Theme.claude : Theme.codex
    }

    private var visibleWindows: [QuotaWindow] {
        guard state.status == .ready || showsLastKnown, let snapshot = state.snapshot else { return [] }
        return WindowVisibility.visible(
            snapshot.windows, provider: provider, showLunaReserve: showLunaReserve,
            hiddenClaudeWindows: hiddenClaudeWindows
        )
        .filter { ($0.resetsAt ?? .distantFuture) > Date() }
    }

    private var showsLastKnown: Bool {
        provider == .claude && [.stale, .credentialExpired, .unavailable].contains(state.status)
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: panelStyle == .rings ? Theme.Layout.ringHeaderSpacing : (panelStyle == .compact ? 6 : 10)
        ) {
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
                    if showsLastKnown {
                        statusMessage
                        if let capturedAt = state.snapshot?.capturedAt {
                            Text("updated.last_known".localized(UsageFormatters.lastUpdated(capturedAt)))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    quotaContent
                }
            }
        }
        .padding(compact ? 9 : (panelStyle == .compact ? 8 : 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: stretchesHeight ? .infinity : nil, alignment: .top)
        .providerCard()
    }

    @ViewBuilder
    private var quotaContent: some View {
        if panelStyle == .rings {
            if visibleWindows.count == 1, let window = visibleWindows.first {
                QuotaRingWindow(
                    window: window, tint: tint, chips: chips(for: window), historical: showsLastKnown,
                    showPace: canShowPace(window), pace: paces[window.id], previousPace: previousPaces[window.id],
                    metrics: .single, alignsTitleRows: false)
            } else {
                ViewThatFits(in: .horizontal) {
                    ringGrid.frame(minWidth: QuotaRingLayout.minimumGridWidth(windows: visibleWindows.count))
                    ringRows
                }
            }
        } else {
            ForEach(Array(visibleWindows.enumerated()), id: \.element.id) { index, window in
                if index > 0 { Divider() }
                if panelStyle == .compact {
                    CompactQuotaWindowRow(
                        window: window, tint: tint, chips: chips(for: window), historical: showsLastKnown,
                        showPace: canShowPace(window), pace: paces[window.id], previousPace: previousPaces[window.id])
                } else {
                    QuotaWindowRow(
                        window: window,
                        tint: tint,
                        chips: chips(for: window),
                        prominent: index == 0 && !showsLastKnown,
                        historical: showsLastKnown,
                        showPace: canShowPace(window), pace: paces[window.id], previousPace: previousPaces[window.id]
                    )
                }
            }
        }
    }

    private var ringGrid: some View {
        QuotaRingGrid {
            ForEach(visibleWindows) { window in
                QuotaRingWindow(
                    window: window, tint: tint, chips: chips(for: window), historical: showsLastKnown,
                    showPace: canShowPace(window), pace: paces[window.id], previousPace: previousPaces[window.id])
            }
        }
    }

    private var ringRows: some View {
        VStack(spacing: Theme.Layout.ringRowSpacing) {
            ForEach(Array(visibleWindows.enumerated()), id: \.element.id) { index, window in
                if index > 0 { Divider() }
                QuotaRingRow(
                    window: window, tint: tint, chips: chips(for: window), historical: showsLastKnown,
                    showPace: canShowPace(window), pace: paces[window.id], previousPace: previousPaces[window.id])
            }
        }
    }

    private func canShowPace(_ window: QuotaWindow) -> Bool {
        showHourlyPace && (state.status == .ready || showsLastKnown) && window.durationMinutes == 10080
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
        guard let window = ProviderStateResolver.menuBarWindow(state: state, selection: menuBarWindows)
        else { return statusText }
        return "quota.remaining_value".localized(UsageFormatters.percentage(window.remainingPercentage))
    }

    @ViewBuilder
    private var header: some View {
        if state.status == .ready, let credits = state.snapshot?.availableResetCredits, credits > 0 {
            ViewThatFits(in: .horizontal) {
                headerRow(credits: credits, reservingStatus: widestFreshness)
                VStack(alignment: .trailing, spacing: 6) {
                    headerRow(credits: nil, reservingStatus: nil)
                    ResetCreditsBadge(count: credits)
                }
            }
        } else {
            headerRow(credits: nil, reservingStatus: nil)
        }
    }

    private var widestFreshness: String {
        UsageFormatters.lastUpdated(Date().addingTimeInterval(-59 * 60))
    }

    private func headerRow(credits: Int?, reservingStatus reserved: String?) -> some View {
        let showsTitle = showProviderTitle || panelStyle == .rings
        return HStack(spacing: 5) {
            if showsTitle {
                ProviderLogo(provider: provider, size: 13)
                Text("provider.\(provider.rawValue)".localized)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            ZStack(alignment: showsTitle ? .trailing : .leading) {
                if let reserved { freshness(reserved).hidden() }
                freshness(statusSubtitle)
            }
            .layoutPriority(2)
            if provider == .claude, let account = accountLabel, !account.isEmpty {
                Group {
                    if hidesAccountLabel {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9, weight: .medium))
                            .help("account.hidden".localized)
                            .accessibilityLabel("account.hidden".localized)
                    } else {
                        Text(account)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityLabel("account.current".localized(account))
                    }
                }
                .foregroundStyle(.secondary)
                .layoutPriority(-1)
            }
            if !showsTitle { Spacer(minLength: 4) }
            if let credits { ResetCreditsBadge(count: credits) }
        }
    }

    private func freshness(_ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        case .credentialExpired: return "status.credential_expired".localized
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
        case .credentialExpired: return "clock.badge.exclamationmark"
        case .accessDenied: return "lock"
        case .cancelled: return "pause.circle"
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .ready: return .green
        case .stale: return .orange
        case .unavailable, .accessDenied: return .red
        case .authenticationRequired, .credentialExpired: return .orange
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
        case .credentialExpired:
            return (claudeAutomaticRecovery ? "message.claude_recovery_retry" : "message.credential_expired").localized
        case .accessDenied:
            return "message.access_denied".localized
        case .cancelled:
            return "message.cancelled".localized
        case .ready:
            return "message.ready".localized
        }
    }
}

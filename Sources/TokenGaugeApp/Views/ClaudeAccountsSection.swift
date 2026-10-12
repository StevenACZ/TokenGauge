import SwiftUI
import TokenGaugeCore

extension ClaudeExtraAccount.Tint {
    var color: Color {
        switch self {
        case .claude: Theme.claude
        case .violet: Theme.accountViolet
        case .blue: Theme.codex
        case .green: Theme.accountGreen
        case .teal: Theme.accountTeal
        case .pink: Theme.accountPink
        }
    }
}

struct ClaudeAccountIcon: View {
    let account: ClaudeExtraAccount

    var body: some View {
        switch account.icon {
        case .dot:
            Circle().fill(account.tint.color).frame(width: 7, height: 7)
        case .balloon:
            HotAirBalloonShape().fill(account.tint.color).frame(width: 10, height: 12)
        case .letter:
            Text(account.initial)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(account.tint.color)
        default:
            Image(systemName: account.icon.symbol ?? "circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(account.tint.color)
        }
    }
}

struct ClaudeAccountsSection: View {
    @ObservedObject var store: ClaudeAccountsStore
    var hiddenWindows: Set<QuotaWindowKind> = []

    var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
                .scrollIndicators(.automatic)
                .frame(height: Theme.Layout.accountsMaxHeight)
        }
        .frame(maxHeight: Theme.Layout.accountsMaxHeight)
        .padding(.horizontal, Theme.Layout.cardPadding)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius).fill(Theme.Layout.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius).strokeBorder(Theme.Layout.cardStroke))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("accounts.title".localized)
    }

    private var rows: some View {
        let accounts = store.visibleAccounts
        let slots =
            accounts.map { ClaudeAccountRow.columns(store.state(for: $0).windows, hidden: hiddenWindows).count }
            .max() ?? 0
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(accounts) { account in
                ClaudeAccountRow(
                    account: account, state: store.state(for: account), hiddenWindows: hiddenWindows, slots: slots
                )
                .contentShape(Rectangle())
                .contextMenu {
                    Button("accounts.make_primary".localized) { store.setPrimary(account.id) }
                    Button("accounts.hide".localized) {
                        var edited = account
                        edited.hidden = true
                        store.update(edited)
                    }
                }
            }
        }
    }
}

struct ClaudeAccountRow: View {
    let account: ClaudeExtraAccount
    let state: ClaudeAccountState
    var hiddenWindows: Set<QuotaWindowKind> = []
    var slots = 0

    static func columns(_ windows: [QuotaWindow], hidden: Set<QuotaWindowKind> = []) -> [QuotaWindow] {
        let shown = windows.filter { window in QuotaWindowKind.of(window).map { !hidden.contains($0) } ?? true }
        let session = shown.first { $0.durationMinutes == 300 }
        let weekly = shown.filter { $0.durationMinutes == 10_080 }.min {
            ($0.remainingPercentage, $0.displayName == nil ? 0 : 1) < (
                $1.remainingPercentage, $1.displayName == nil ? 0 : 1
            )
        }
        return [session, weekly].compactMap { $0 }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                ClaudeAccountIcon(account: account).frame(width: 12)
                Text(account.name.isEmpty ? "accounts.unnamed".localized : account.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: 74, alignment: .leading)
            if state.status == .ready || !state.windows.isEmpty {
                let columns = Self.columns(state.windows, hidden: hiddenWindows)
                ForEach(columns) { window in
                    column(window)
                }
                ForEach(columns.count..<max(slots, columns.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            } else {
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func column(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window.durationMinutes == 300 ? "accounts.session".localized : weeklyLabel(window))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(UsageFormatters.percentage(window.remainingPercentage))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.severity(remaining: window.remainingPercentage) ?? .primary)
            }
            GaugeBar(
                fraction: window.remainingPercentage / 100,
                tint: Theme.severity(remaining: window.remainingPercentage) ?? account.tint.color)
            Text(UsageFormatters.reset(window.resetsAt))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weeklyLabel(_ window: QuotaWindow) -> String {
        window.displayName ?? "accounts.weekly".localized
    }

    private var statusText: String {
        switch state.status {
        case .loading: "accounts.status.loading".localized
        case .ready: ""
        case .signedOut: "accounts.status.signed_out".localized
        case .expired: "accounts.status.expired".localized
        case .noAccess: "accounts.status.no_access".localized
        case .rateLimited: "accounts.status.rate_limited".localized
        case .unreachable: "accounts.status.unreachable".localized
        case .invalidLocation: "accounts.status.invalid".localized
        }
    }
}

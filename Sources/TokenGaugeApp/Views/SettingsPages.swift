import AppKit
import SwiftUI
import TokenGaugeCore

struct SettingsPanelPage: View {
    @ObservedObject var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageHeader(page: .panel)
            SettingsSection(title: "settings.panel_style".localized) {
                HStack(spacing: 8) {
                    ForEach(QuotaPanelStyle.allCases) { style in
                        ChoiceTile(
                            title: style.titleKey.localized, selected: store.panelStyle == style,
                            action: { change { store.panelStyle = style } }
                        ) {
                            Image(systemName: style.symbol)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(store.panelStyle == style ? Color.accentColor : .secondary)
                        }
                    }
                }
            }
            SettingsSection(title: "settings.panel.limits".localized) {
                HStack(spacing: 10) {
                    ProviderLogo(provider: .claude, size: 15).frame(width: 20)
                    Text("provider.claude".localized).font(.callout)
                    Spacer(minLength: 8)
                    ForEach(QuotaWindowKind.allCases) { kind in
                        let visible = store.isClaudeWindowVisible(kind)
                        QuotaChip(title: windowLabel(kind), tint: Theme.claude, selected: visible) {
                            change { store.setClaudeWindow(kind, visible: !visible) }
                        }
                        .help(QuotaWindowNames.name(kind, snapshot: store.claude.snapshot))
                        .accessibilityLabel(
                            "settings.claude_windows".localized + " · "
                                + QuotaWindowNames.name(kind, snapshot: store.claude.snapshot))
                    }
                }
                SettingsToggleRow(
                    title: "settings.show_reserve".localized, symbol: "moon",
                    help: "settings.show_reserve_help".localized, isOn: $store.showLunaReserve)
            }
            SettingsSection(title: "settings.panel.behavior".localized) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 20)
                    Text("history.view".localized).font(.callout).lineLimit(1)
                    Spacer(minLength: 8)
                    Picker("history.view".localized, selection: $store.historyMode) {
                        ForEach(HistoryMode.allCases) { mode in
                            Text(mode.titleKey.localized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                }
                SettingsToggleRow(
                    title: "settings.animate_changes".localized, symbol: "sparkles",
                    help: "settings.animate_changes_help".localized, isOn: $store.animateChanges)
                SettingsToggleRow(
                    title: "pace.setting".localized, symbol: "gauge.with.dots.needle.33percent",
                    isOn: $store.showHourlyPace)
            }
        }
    }

    private func change(_ update: () -> Void) {
        withAnimation(store.animateChanges && !reduceMotion ? Theme.Motion.content : nil, update)
    }

    private func windowLabel(_ kind: QuotaWindowKind) -> String {
        if let window = store.claude.snapshot?.windows.first(where: { QuotaWindowKind.of($0) == kind }) {
            return MenuBarPresentation.shortLabel(window)
        }
        switch kind {
        case .session: return "menu.label.session".localized
        case .weekly: return "menu.label.weekly".localized
        case .modelWeekly: return "settings.claude_model_placeholder".localized
        }
    }
}

struct SettingsAccountsPage: View {
    @ObservedObject var store: UsageStore
    var accounts = ClaudeAccountsStore.shared
    @AppStorage(AppPreferences.Key.codexExecutablePath) private var codexExecutablePath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageHeader(page: .accounts)
            VStack(spacing: 10) {
                ForEach([UsageProvider.codex, .claude], id: \.self) { provider in
                    providerCard(provider)
                }
            }
            SettingsSection(title: "accounts.title".localized) {
                ClaudeAccountsSettings(store: accounts)
            }
        }
    }

    private func providerCard(_ provider: UsageProvider) -> some View {
        let tint = provider == .codex ? Theme.codex : Theme.claude
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderLogo(provider: provider, size: 18)
                Text("provider.\(provider.rawValue)".localized).font(.headline)
                StatusPill(title: statusTitle(for: provider), color: statusColor(for: provider))
                Spacer(minLength: 6)
                if provider == .codex {
                    Menu {
                        Button("setup.choose_codex".localized, action: chooseCodex)
                        if !codexExecutablePath.isEmpty {
                            Button("setup.automatic".localized) {
                                codexExecutablePath = ""
                                store.refresh(force: true)
                            }
                        }
                    } label: {
                        Text("setup.detection".localized)
                    }
                    .menuStyle(.borderlessButton).controlSize(.small).fixedSize()
                    .help(codexExecutablePath.isEmpty ? "setup.automatic".localized : codexExecutablePath)
                }
                Link(destination: provider == .codex ? AppLinks.codexSetup : AppLinks.claudeSetup) {
                    Label("setup.connect".localized, systemImage: "arrow.up.right.square")
                }
                .help(provider == .claude ? "setup.claude_session".localized : "setup.connect".localized)
            }
            .font(.caption)
            SettingsToggleRow(
                title: "settings.mark_cancelled".localized, symbol: "xmark.seal",
                help: "settings.cancellation_help".localized,
                isOn: Binding(
                    get: { store.isCancelled(provider: provider) }, set: { store.setCancelled($0, for: provider) }))
            if provider == .claude {
                SettingsToggleRow(
                    title: "settings.claude_recovery".localized, symbol: "arrow.triangle.2.circlepath",
                    help: "settings.claude_recovery_help".localized, isOn: $store.claudeAutomaticRecovery)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.22)))
    }

    private func statusTitle(for provider: UsageProvider) -> String {
        switch store.state(for: provider).status {
        case .ready: return "settings.access_confirmed".localized
        case .loading: return "status.loading".localized
        case .waiting: return "status.waiting".localized
        case .stale: return "status.stale".localized
        case .unavailable: return "status.unavailable".localized
        case .authenticationRequired: return "status.authentication_required".localized
        case .credentialExpired: return "status.credential_expired".localized
        case .accessDenied: return "status.access_denied".localized
        case .cancelled: return "status.cancelled".localized
        }
    }

    private func statusColor(for provider: UsageProvider) -> Color {
        switch store.state(for: provider).status {
        case .ready: return .green
        case .authenticationRequired, .credentialExpired, .accessDenied, .stale: return .orange
        default: return .secondary
        }
    }

    private func chooseCodex() {
        let panel = NSOpenPanel()
        panel.title = "setup.choose_codex".localized
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url,
            FileManager.default.isExecutableFile(atPath: url.path)
        else { return }
        codexExecutablePath = url.path
        store.refresh(force: true)
    }
}

struct SettingsGeneralPage: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var updates = UpdateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageHeader(page: .general)
            SettingsSection(title: "settings.general.app".localized) {
                HStack(spacing: 10) {
                    Image(systemName: "globe").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 20)
                    Text("settings.language".localized).font(.callout)
                    Spacer(minLength: 8)
                    Picker("settings.language".localized, selection: $localization.language) {
                        Text(verbatim: "Español").tag(AppLanguage.spanish)
                        Text(verbatim: "English").tag(AppLanguage.english)
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                }
                SettingsToggleRow(
                    title: "settings.launch_at_login".localized, symbol: "power",
                    isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }))
                if let message = launchAtLogin.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsToggleRow(
                    title: "settings.hide_account".localized, symbol: "eye.slash",
                    help: "settings.hide_account_help".localized, isOn: $store.hideAccountLabel)
                if updates.available {
                    SettingsToggleRow(
                        title: "updates.automatic".localized, symbol: "arrow.down.circle",
                        help: "updates.explanation".localized,
                        isOn: Binding(get: { updates.autoCheckEnabled }, set: { updates.setAutoCheckEnabled($0) }))
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "desktopcomputer").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary).frame(width: 20)
                        Text("updates.local".localized).font(.callout)
                        InfoTip(text: "updates.development".localized)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 26)
                }
            }
            SettingsSection(title: "setup.privacy".localized) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("setup.permissions".localized)
                    Text("setup.local_history".localized)
                }
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

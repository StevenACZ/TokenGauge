import AppKit
import SwiftUI
import TokenGaugeCore

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var updates = UpdateManager.shared
    @AppStorage("codexExecutablePath") private var codexExecutablePath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("settings.title".localized, systemImage: "slider.horizontal.3")
                .font(.system(size: 22, weight: .semibold))
                .padding(.bottom, 2)

            section("settings.general".localized) {
                VStack(spacing: 12) {
                    preferenceRow("settings.language".localized) {
                        Picker("settings.language".localized, selection: $localization.language) {
                            Text("Español").tag(AppLanguage.spanish)
                            Text("English").tag(AppLanguage.english)
                        }.labelsHidden().frame(width: 160, alignment: .trailing)
                    }
                    Divider()
                    preferenceRow("settings.display_mode".localized) {
                        Picker("settings.display_mode".localized, selection: $store.displayMode) {
                            ForEach(UsageDisplayMode.allCases) { mode in
                                Label {
                                    Text(mode.titleKey.localized)
                                } icon: {
                                    displayModeImage(mode)
                                }.tag(mode)
                            }
                        }.labelsHidden().frame(width: 160, alignment: .trailing)
                    }
                    Divider()
                    preferenceRow("settings.menu_bar_size".localized) {
                        Picker("settings.menu_bar_size".localized, selection: $store.menuBarSize) {
                            ForEach(MenuBarSize.allCases) { size in
                                Text(size.titleKey.localized).tag(size)
                            }
                        }.labelsHidden().frame(width: 160, alignment: .trailing)
                    }
                    Divider()
                    preferenceRow("settings.launch_at_login".localized) {
                        Toggle(
                            "settings.launch_at_login".localized,
                            isOn: Binding(
                                get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })
                        )
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    if let message = launchAtLogin.errorMessage {
                        Text(message).font(.caption).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(16).settingsSurface()
            }

            section("settings.appearance".localized) {
                VStack(spacing: 12) {
                    preferenceRow("settings.panel_style".localized) {
                        Picker("settings.panel_style".localized, selection: $store.panelStyle) {
                            ForEach(QuotaPanelStyle.allCases) { style in
                                Label(style.titleKey.localized, systemImage: style.symbol).tag(style)
                            }
                        }.labelsHidden().frame(width: 170)
                    }
                    Divider()
                    preferenceRow("settings.indicator_style".localized) {
                        Picker("settings.indicator_style".localized, selection: $store.menuBarStyle) {
                            ForEach(QuotaMenuBarStyle.allCases) { style in
                                Text(style.titleKey.localized).tag(style)
                            }
                        }.labelsHidden().frame(width: 170)
                    }
                    Text("settings.indicator_style_help".localized)
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    preferenceRow("settings.animate_changes".localized) {
                        Toggle("settings.animate_changes".localized, isOn: $store.animateChanges)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    Text("settings.animate_changes_help".localized)
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(16).settingsSurface()
            }

            section("settings.providers".localized) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(UsageProvider.allCases, id: \.self) { provider in
                        providerSettings(provider)
                    }
                }
                Text("settings.cancellation_help".localized)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2).padding(.top, 2)
                DisclosureGroup("setup.privacy".localized) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("setup.permissions".localized)
                        Text("setup.local_history".localized)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                }.font(.caption).padding(.top, 2)
            }

            section("updates.title".localized) {
                VStack(alignment: .leading, spacing: 10) {
                    if updates.available {
                        preferenceRow("updates.automatic".localized) {
                            Toggle(
                                "updates.automatic".localized,
                                isOn: Binding(
                                    get: { updates.autoCheckEnabled }, set: { updates.setAutoCheckEnabled($0) })
                            )
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        }
                        Text("updates.explanation".localized).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    } else {
                        Label("updates.local".localized, systemImage: "desktopcomputer")
                            .font(.callout.weight(.medium)).frame(maxWidth: .infinity)
                        Text("updates.development".localized).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).settingsSurface()
            }
        }
        .padding(24)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin.refresh() }
        .id(localization.language)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            content()
        }
    }

    private func preferenceRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 24) {
            Text(title).font(.callout)
            Spacer(minLength: 16)
            control()
        }.frame(minHeight: 24)
    }

    private func providerSettings(_ provider: UsageProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderLogo(provider: provider, size: 18)
                Text("provider.\(provider.rawValue)".localized).font(.headline)
            }
            Label(statusTitle(for: provider), systemImage: "circle.fill")
                .font(.caption).foregroundStyle(statusColor(for: provider))
                .labelStyle(.titleAndIcon)
            HStack(spacing: 12) {
                Text("settings.mark_cancelled".localized).font(.callout)
                Spacer(minLength: 0)
                Toggle(
                    "settings.mark_cancelled".localized,
                    isOn: Binding(
                        get: { store.isCancelled(provider: provider) },
                        set: { store.setCancelled($0, for: provider) })
                )
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(
                    "provider.\(provider.rawValue)".localized + " · " + "settings.mark_cancelled".localized)
            }.frame(minHeight: 24)
            Divider()
            Link(destination: provider == .codex ? AppLinks.codexSetup : AppLinks.claudeSetup) {
                Label("setup.connect".localized, systemImage: "arrow.up.right.square")
            }.font(.callout)
            Group {
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
                    .menuStyle(.borderlessButton).fixedSize()
                    .help(codexExecutablePath.isEmpty ? "setup.automatic".localized : codexExecutablePath)
                } else {
                    Text("setup.claude_session".localized).foregroundStyle(.secondary)
                }
            }.font(.caption).frame(height: 20, alignment: .leading)
            if provider == .codex {
                Divider()
                HStack(spacing: 12) {
                    Text("settings.show_reserve".localized).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Toggle("settings.show_reserve".localized, isOn: $store.showLunaReserve)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .help("settings.show_reserve_help".localized)
                }.frame(minHeight: 24)
            } else {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("settings.claude_recovery".localized, isOn: $store.claudeAutomaticRecovery)
                        .toggleStyle(.switch).controlSize(.small)
                    Text("settings.claude_recovery_help".localized)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                claudeWindowSettings
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).settingsSurface()
    }

    private var claudeWindowSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.claude_windows".localized).font(.caption).foregroundStyle(.secondary)
            ForEach(ClaudeWindowKind.allCases) { kind in
                HStack(spacing: 12) {
                    Text(claudeWindowName(kind)).font(.callout)
                    Spacer(minLength: 0)
                    Toggle(
                        claudeWindowName(kind),
                        isOn: Binding(
                            get: { store.isClaudeWindowVisible(kind) },
                            set: { store.setClaudeWindow(kind, visible: $0) })
                    )
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("settings.claude_windows".localized + " · " + claudeWindowName(kind))
                }.frame(minHeight: 24)
            }
            Divider()
            HStack(spacing: 12) {
                Text("settings.claude_menu_bar".localized).font(.callout)
                Spacer(minLength: 0)
                Picker("settings.claude_menu_bar".localized, selection: $store.claudeMenuBarSource) {
                    ForEach(ClaudeMenuBarSource.allCases) { source in
                        Text(source.kind.map(claudeWindowName) ?? "settings.claude_menu_bar.automatic".localized)
                            .tag(source)
                    }
                }.labelsHidden().frame(width: 150, alignment: .trailing)
            }.frame(minHeight: 24)
            Text("settings.claude_menu_bar_help".localized).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func claudeWindowName(_ kind: ClaudeWindowKind) -> String {
        switch kind {
        case .session: return "window.session".localized
        case .weekly: return "window.weekly".localized
        case .modelWeekly:
            let scoped = store.claude.snapshot?.windows.first { ClaudeWindowKind.of($0) == .modelWeekly }
            return "window.model_weekly".localized(scoped?.displayName ?? "settings.claude_model_placeholder".localized)
        }
    }

    private func displayModeImage(_ mode: UsageDisplayMode) -> Image {
        let source: NSImage?
        if let provider = mode.singleProvider {
            source = ProviderLogoAssets.menuBarImage(for: provider, size: 14)
        } else {
            source = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil)
        }
        guard let source else { return Image(systemName: "square.grid.2x2.fill") }
        let padded = NSImage(size: NSSize(width: 20, height: 14), flipped: false) { _ in
            source.draw(in: NSRect(x: 0, y: 0, width: 14, height: 14))
            return true
        }
        padded.isTemplate = source.isTemplate
        return Image(nsImage: padded)
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

private struct SettingsSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06)))
    }
}

extension View {
    fileprivate func settingsSurface() -> some View { modifier(SettingsSurface()) }
}

enum AppLinks {
    static let repository = URL(string: "https://github.com/StevenACZ/TokenGauge")!
    static let issues = repository.appendingPathComponent("issues")
    static let releases = repository.appendingPathComponent("releases")
    static let codexSetup = URL(string: "https://developers.openai.com/codex/cli/")!
    static let claudeSetup = URL(string: "https://code.claude.com/docs/en/quickstart")!
}

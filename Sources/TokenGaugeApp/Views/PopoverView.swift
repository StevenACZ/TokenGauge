import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            header
            ProviderCard(provider: .claude, state: store.claude)
            ProviderCard(provider: .codex, state: store.codex)
            ActivityChartView(claude: store.claude.snapshot, codex: store.codex.snapshot)
            Divider().padding(.top, 1)
            footer
        }
        .padding(.horizontal, Theme.Layout.panelPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: Theme.Layout.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .id(localization.language)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.claude.opacity(0.9), Theme.codex.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)

            Text("app.name".localized)
                .font(.system(size: 14, weight: .semibold))

            Spacer(minLength: 0)

            Button {
                store.refresh(force: true)
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.borderless)
            .help("action.refresh".localized)
            .disabled(store.isRefreshing)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            SettingRow(icon: "powerplug", title: "settings.launch_at_login".localized) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .labelsHidden()
                .controlSize(.mini)

                Picker("", selection: $localization.language) {
                    Text("language.spanish".localized).tag(AppLanguage.spanish)
                    Text("language.english".localized).tag(AppLanguage.english)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .help("settings.language".localized)
            }

            if let message = launchAtLogin.errorMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 4)
            }

            FooterActionRow(icon: "power", title: "action.quit".localized) {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct SettingRow<Accessory: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 15)
            Text(title)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            accessory
        }
        .padding(.horizontal, 5)
        .frame(height: 28)
    }
}

private struct FooterActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 15)
                Text(title)
                    .font(.caption)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.rowRadius, style: .continuous)
                    .fill(hovered ? Color.primary.opacity(0.07) : Color.clear)
            )
            .foregroundStyle(Color.red)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

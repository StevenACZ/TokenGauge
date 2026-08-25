import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            ProviderCard(provider: .claude, state: store.claude)
            ProviderCard(provider: .codex, state: store.codex)
            ActivityChartView(claude: store.claude.snapshot, codex: store.codex.snapshot)
            Divider()
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: Theme.Layout.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .id(localization.language)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.claude.opacity(0.18), Theme.codex.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.codex)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text("app.name".localized)
                    .font(.headline)
                Text("app.subtitle".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                store.refresh(force: true)
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("action.refresh".localized)
            .disabled(store.isRefreshing)
        }
    }

    private var footer: some View {
        VStack(spacing: 3) {
            FooterSettingsRow(
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ),
                language: $localization.language
            )
            FooterActionRow(icon: "power", title: "action.quit".localized, destructive: true) {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct FooterSettingsRow: View {
    @Binding var isOn: Bool
    @Binding var language: AppLanguage

    var body: some View {
        HStack {
            Label("settings.launch_at_login".localized, systemImage: "powerplug")
                .foregroundStyle(.primary)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .controlSize(.small)
            Spacer()
            Picker("settings.language".localized, selection: $language) {
                Text("language.spanish".localized).tag(AppLanguage.spanish)
                Text("language.english".localized).tag(AppLanguage.english)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
    }
}

private struct FooterActionRow: View {
    let icon: String
    let title: String
    let destructive: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.rowRadius, style: .continuous)
                    .fill(hovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

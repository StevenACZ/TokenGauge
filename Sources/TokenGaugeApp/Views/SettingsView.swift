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
        VStack(alignment: .leading, spacing: 20) {
            Label("settings.title".localized, systemImage: "slider.horizontal.3")
                .font(.title2.bold())
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("settings.language".localized, selection: $localization.language) {
                        Text("Español").tag(AppLanguage.spanish)
                        Text("English").tag(AppLanguage.english)
                    }
                    Picker("settings.primary_provider".localized, selection: $store.primaryProvider) {
                        Text("Codex").tag(UsageProvider.codex)
                        Text("Claude Code").tag(UsageProvider.claude)
                    }
                    Toggle(
                        "settings.launch_at_login".localized,
                        isOn: Binding(
                            get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }))
                    if let message = launchAtLogin.errorMessage {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                    Toggle(
                        "settings.claude_cancelled".localized,
                        isOn: Binding(
                            get: { store.claudeCancelledAt != nil }, set: { store.setClaudeCancelled($0) }))
                    Text("settings.cancellation_help".localized)
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(10)
            }
            GroupBox("setup.title".localized) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("setup.description".localized)
                    HStack {
                        Link("setup.codex".localized, destination: AppLinks.codexSetup)
                        Spacer()
                        Link("setup.claude".localized, destination: AppLinks.claudeSetup)
                    }
                    HStack {
                        Button("setup.choose_codex".localized, action: chooseCodex)
                        if !codexExecutablePath.isEmpty {
                            Button("setup.automatic".localized) {
                                codexExecutablePath = ""
                                store.refresh(force: true)
                            }
                        }
                    }
                    if !codexExecutablePath.isEmpty {
                        Text(codexExecutablePath).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle)
                    }
                    Text("setup.permissions".localized)
                        .foregroundStyle(.secondary)
                }.font(.callout).padding(10)
            }
            GroupBox("updates.title".localized) {
                VStack(alignment: .leading, spacing: 10) {
                    if updates.available {
                        Toggle(
                            "updates.automatic".localized,
                            isOn: Binding(
                                get: { updates.autoCheckEnabled }, set: { updates.setAutoCheckEnabled($0) }))
                        Text("updates.explanation".localized)
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("updates.development".localized).font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
        }
        .padding(24)
        .frame(width: 470)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin.refresh() }
        .id(localization.language)
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

enum AppLinks {
    static let repository = URL(string: "https://github.com/StevenACZ/TokenGauge")!
    static let issues = repository.appendingPathComponent("issues")
    static let releases = repository.appendingPathComponent("releases")
    static let codexSetup = URL(string: "https://developers.openai.com/codex/cli/")!
    static let claudeSetup = URL(string: "https://code.claude.com/docs/en/quickstart")!
}

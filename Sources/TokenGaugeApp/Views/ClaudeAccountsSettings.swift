import SwiftUI
import TokenGaugeCore

struct ClaudeAccountsSettings: View {
    @ObservedObject var store: ClaudeAccountsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsToggleRow(
                title: "accounts.enable".localized, symbol: "person.2",
                help: "accounts.enable_help".localized, isOn: $store.enabled)
            if store.enabled {
                ForEach(store.accounts) { account in
                    ClaudeAccountEditor(account: account, state: store.state(for: account), store: store)
                }
                Button {
                    store.add()
                } label: {
                    Label("accounts.add".localized, systemImage: "plus")
                }
                .controlSize(.small)
                Text("accounts.location_help".localized)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ClaudeAccountEditor: View {
    let account: ClaudeExtraAccount
    let state: ClaudeAccountState
    let store: ClaudeAccountsStore

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .help(statusHelp)
            Menu {
                ForEach(ClaudeExtraAccount.Icon.allCases, id: \.self) { icon in
                    Button {
                        var edited = account
                        edited.icon = icon
                        store.update(edited)
                    } label: {
                        Label {
                            Text("accounts.icon.\(icon.rawValue)".localized)
                        } icon: {
                            if let image = AccountIconArt.image(icon, color: .labelColor, size: 14) {
                                Image(nsImage: image)
                            }
                        }
                    }
                }
            } label: {
                ClaudeAccountIcon(account: account)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("accounts.icon".localized)
            .accessibilityLabel("accounts.icon".localized)
            TextField("accounts.name".localized, text: binding(\.name))
                .textFieldStyle(.roundedBorder).controlSize(.small)
                .frame(width: 140)
            TextField("accounts.location_placeholder".localized, text: binding(\.location))
                .textFieldStyle(.roundedBorder).controlSize(.small)
                .font(.system(size: 11, design: .monospaced))
            HStack(spacing: 5) {
                ForEach(ClaudeExtraAccount.Tint.allCases, id: \.self) { tint in
                    Button {
                        var edited = account
                        edited.tint = tint
                        store.update(edited)
                    } label: {
                        Circle()
                            .fill(tint.color)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(
                                    Color.primary.opacity(account.tint == tint ? 0.6 : 0), lineWidth: 2)
                            )
                            .padding(2)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("accounts.tint.\(tint.rawValue)".localized)
                    .accessibilityAddTraits(account.tint == tint ? [.isSelected] : [])
                }
            }
            Button {
                var edited = account
                edited.showsInMenuBar.toggle()
                store.update(edited)
            } label: {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        account.showsInMenuBar ? AnyShapeStyle(account.tint.color) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.borderless)
            .help("accounts.menu_bar".localized)
            .accessibilityLabel("accounts.menu_bar".localized)
            .accessibilityAddTraits(account.showsInMenuBar ? [.isSelected] : [])
            Button {
                store.remove(account.id)
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("accounts.remove".localized)
            .accessibilityLabel("accounts.remove".localized)
        }
    }

    private func binding(_ field: WritableKeyPath<ClaudeExtraAccount, String>) -> Binding<String> {
        Binding(
            get: { account[keyPath: field] },
            set: { value in
                var edited = account
                edited[keyPath: field] = value
                store.update(edited)
            })
    }

    private var dotColor: Color {
        switch state.status {
        case .ready: .green
        case .loading: .secondary.opacity(0.4)
        case .rateLimited: .orange
        default: .red
        }
    }

    private var statusHelp: String {
        switch state.status {
        case .ready: "accounts.status.ready".localized
        case .loading: "accounts.status.loading".localized
        case .signedOut: "accounts.status.signed_out".localized
        case .expired: "accounts.status.expired".localized
        case .noAccess: "accounts.status.no_access".localized
        case .rateLimited: "accounts.status.rate_limited".localized
        case .unreachable: "accounts.status.unreachable".localized
        case .invalidLocation: "accounts.status.invalid".localized
        }
    }
}

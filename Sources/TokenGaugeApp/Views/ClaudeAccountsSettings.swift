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

@MainActor
enum AccountSchedule {
    static let week = [2, 3, 4, 5, 6, 7, 1]

    static func summary(_ account: ClaudeExtraAccount) -> String {
        if account.hidden { return "accounts.days.hidden".localized }
        let days = week.indices.filter { !account.hiddenWeekdays.contains(week[$0]) }
        if days.count == week.count { return "accounts.days.every".localized }
        guard let first = days.first, let last = days.last else { return "accounts.days.none".localized }
        if days.count >= 3, last - first == days.count - 1 {
            return "accounts.days.range".localized(symbol(week[first]), symbol(week[last]))
        }
        if days.count > 2 { return "accounts.days.count".localized(days.count) }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: days.map { symbol(week[$0]) }) ?? ""
    }

    static func symbol(_ weekday: Int, wide: Bool = false) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = wide ? calendar.standaloneWeekdaySymbols : calendar.shortStandaloneWeekdaySymbols
        return symbols[weekday - 1].capitalized
    }

    private static var locale: Locale { Locale(identifier: LocalizationManager.shared.language.rawValue) }
}

extension ClaudeAccountsStore {
    fileprivate func edit(_ account: ClaudeExtraAccount, _ change: (inout ClaudeExtraAccount) -> Void) {
        var edited = account
        change(&edited)
        update(edited)
    }
}

private struct ClaudeAccountEditor: View {
    let account: ClaudeExtraAccount
    let state: ClaudeAccountState
    let store: ClaudeAccountsStore
    @State private var editsDays = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .help(statusHelp)
                look
                TextField("accounts.name".localized, text: binding(\.name))
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                    .frame(width: 120)
                TextField("accounts.location_placeholder".localized, text: binding(\.location))
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                    .font(.system(size: 11, design: .monospaced))
            }
            .opacity(account.hidden ? 0.55 : 1)
            days
            primaryButton
            Button {
                store.edit(account) { $0.showsInMenuBar.toggle() }
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

    private var primaryButton: some View {
        let isPrimary = store.primaryID == account.id
        return Button {
            store.setPrimary(isPrimary ? nil : account.id)
        } label: {
            Image(systemName: isPrimary ? "star.fill" : "star")
                .font(.system(size: 12))
                .foregroundStyle(isPrimary ? AnyShapeStyle(account.tint.color) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.borderless)
        .help("accounts.primary_help".localized)
        .accessibilityLabel("accounts.primary".localized)
        .accessibilityAddTraits(isPrimary ? [.isSelected] : [])
    }

    private var look: some View {
        Menu {
            Picker("accounts.icon".localized, selection: binding(\.icon)) {
                ForEach(ClaudeExtraAccount.Icon.allCases, id: \.self) { icon in
                    Label {
                        Text("accounts.icon.\(icon.rawValue)".localized)
                    } icon: {
                        mark(icon, tint: account.tint, size: 14)
                    }
                    .tag(icon)
                }
            }
            .pickerStyle(.inline)
            Picker("accounts.color".localized, selection: binding(\.tint)) {
                ForEach(ClaudeExtraAccount.Tint.allCases, id: \.self) { tint in
                    Label {
                        Text("accounts.tint.\(tint.rawValue)".localized)
                    } icon: {
                        Image(nsImage: AccountIconArt.swatch(NSColor(tint.color), size: 14))
                    }
                    .tag(tint)
                }
            }
            .pickerStyle(.inline)
        } label: {
            mark(account.icon, tint: account.tint, size: 13)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(width: 34, alignment: .leading)
        .help("accounts.look".localized)
        .accessibilityLabel("accounts.look".localized)
    }

    @ViewBuilder
    private func mark(_ icon: ClaudeExtraAccount.Icon, tint: ClaudeExtraAccount.Tint, size: CGFloat) -> some View {
        if let image = AccountIconArt.image(icon, letter: account.initial, color: NSColor(tint.color), size: size) {
            Image(nsImage: image)
        }
    }

    private var days: some View {
        let summary = AccountSchedule.summary(account)
        return Button {
            editsDays.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: account.hidden ? "eye.slash" : "eye").frame(width: 16)
                Text(summary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11))
            .foregroundStyle(account.hidden ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .frame(width: Self.daysWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("accounts.days_help".localized)
        .accessibilityLabel("accounts.days".localized + " · " + summary)
        .popover(isPresented: $editsDays, arrowEdge: .bottom) {
            AccountDaysPicker(account: account, store: store)
        }
    }

    private static let daysWidth: CGFloat = 116

    private func binding<Value>(_ field: WritableKeyPath<ClaudeExtraAccount, Value>) -> Binding<Value> {
        Binding(
            get: { account[keyPath: field] },
            set: { value in store.edit(account) { $0[keyPath: field] = value } })
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

struct AccountDaysPicker: View {
    let account: ClaudeExtraAccount
    let store: ClaudeAccountsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsToggleRow(
                title: "accounts.show".localized, symbol: "eye",
                isOn: Binding(get: { !account.hidden }, set: { shown in store.edit(account) { $0.hidden = !shown } }))
            HStack(spacing: 5) {
                ForEach(AccountSchedule.week, id: \.self) { weekday in
                    let shown = !account.hiddenWeekdays.contains(weekday)
                    Button {
                        store.edit(account) { $0.hiddenWeekdays.formSymmetricDifference([weekday]) }
                    } label: {
                        Text(AccountSchedule.symbol(weekday))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(shown ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .frame(width: 34, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(account.tint.color.opacity(shown ? 0.22 : 0))
                            )
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AccountSchedule.symbol(weekday, wide: true))
                    .accessibilityAddTraits(shown ? [.isSelected] : [])
                }
            }
            .disabled(account.hidden)
            .opacity(account.hidden ? 0.45 : 1)
            Text("accounts.days_help".localized)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 296)
    }
}

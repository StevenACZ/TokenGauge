import AppKit
import SwiftUI
import TokenGaugeCore

struct MenuBarDesigner: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var accounts: ClaudeAccountsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tour: MenuBarTourState?
    @State private var playing = false

    private static let sizes: [MenuBarSize] = [.small, .medium, .large]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageHeader(page: .menuBar) {
                Button {
                    if playing { stop() } else { playing = true }
                } label: {
                    Label(
                        (playing ? "settings.tour.stop" : "settings.tour.show").localized,
                        systemImage: playing ? "stop.fill" : "play.fill")
                }
                .controlSize(.small)
                .accessibilityIdentifier("TokenGauge.settings.tour")
            }
            MenuBarTourStage(
                presentation: presentation, mode: store.displayMode, privacy: store.hideAccountLabel, state: tour,
                motion: motion)
            SettingsSection(title: "settings.menu_bar.show".localized) {
                ForEach([UsageProvider.codex, .claude], id: \.self) { provider in
                    providerRow(provider)
                }
                if accounts.enabled, !accounts.accounts.isEmpty { accountsRow }
            }
            SettingsSection(title: "settings.menu_bar.look".localized) {
                HStack(spacing: 8) {
                    ForEach(QuotaMenuBarStyle.allCases) { style in
                        ChoiceTile(
                            title: style.titleKey.localized, selected: store.menuBarStyle == style,
                            action: { change { store.menuBarStyle = style } }
                        ) {
                            Image(nsImage: preview(style))
                                .resizable().interpolation(.high).scaledToFit()
                                .frame(maxHeight: 18)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                        }
                    }
                }
                sizeRow
            }
        }
        .task(id: playing) {
            guard playing else { return }
            await play()
        }
    }

    private var motion: Bool { store.animateChanges && !reduceMotion }

    private var appearance: NSAppearance {
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance
    }

    private var presentation: MenuBarPresentation {
        MenuBarPresentation(
            providers: store.displayMode.providers, state: { store.state(for: $0) }, appearance: appearance,
            size: store.menuBarSize, style: store.menuBarStyle, selection: store.menuBarSelections,
            accounts: store.isInMenuBar(.claude) ? accounts.menuBarAccounts : [])
    }

    private func preview(_ style: QuotaMenuBarStyle) -> NSImage {
        MenuBarPresentation(
            providers: [store.displayMode.providers.last ?? .claude], state: { store.state(for: $0) },
            appearance: appearance, size: .medium,
            style: style, selection: store.menuBarSelections
        ).renderedImage()
    }

    private func change(_ update: () -> Void) {
        withAnimation(motion ? Theme.Motion.content : nil, update)
    }

    private func play() async {
        let animated = motion
        for (state, seconds) in MenuBarTourState.script(animated: animated) {
            withAnimation(animated ? Self.animation(state.phase) : nil) { tour = state }
            guard (try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))) != nil else { return }
        }
        stop()
    }

    private func stop() {
        playing = false
        withAnimation(motion ? Theme.Motion.content : nil) { tour = nil }
    }

    private static func animation(_ phase: MenuBarTourState.Phase) -> Animation {
        switch phase {
        case .rest: Theme.Motion.content
        case .point: .easeInOut(duration: 0.65)
        case .press: .easeOut(duration: 0.3)
        case .open: .spring(response: 0.3, dampingFraction: 0.82)
        }
    }

    private func providerRow(_ provider: UsageProvider) -> some View {
        let shown = store.isInMenuBar(provider)
        let isOnly = shown && store.displayMode.providers.count == 1
        let state = store.state(for: provider)
        let kinds = ProviderStateResolver.menuBarKinds(snapshot: state.snapshot, provider: provider)
        let selection = store.menuBarSelection(for: provider)
        let automatic = Set(
            ProviderStateResolver.menuBarWindows(state: state).compactMap {
                QuotaWindowKind.of($0, provider: provider)
            })
        let candidates = state.snapshot.map { ProviderStateResolver.menuBarCandidates($0) } ?? []
        let tint = provider == .codex ? Theme.codex : Theme.claude
        return HStack(spacing: 8) {
            QuotaChip(
                title: "provider.\(provider.rawValue)".localized, provider: provider, tint: tint, selected: shown
            ) {
                change { store.setInMenuBar(!shown, provider: provider) }
            }
            .disabled(isOnly)
            .help("settings.menu_bar.provider_help".localized)
            .frame(width: 112, alignment: .leading)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 18)
            HStack(spacing: 6) {
                if kinds.count > 1 {
                    QuotaChip(title: "settings.menu_bar.auto".localized, tint: tint, selected: selection.isEmpty) {
                        change { store.setMenuBarSelection([], for: provider) }
                    }
                    .help("settings.claude_menu_bar_help".localized)
                }
                ForEach(kinds) { kind in
                    let window = candidates.first { QuotaWindowKind.of($0, provider: provider) == kind }
                    QuotaChip(
                        title: window.map { MenuBarPresentation.shortLabel($0, provider: provider) }
                            ?? fallbackLabel(kind),
                        detail: window.map { "\(Int($0.remainingPercentage.rounded()))%" },
                        tint: tint,
                        selected: selection.contains(kind) || (kinds.count == 1 && shown),
                        automatic: selection.isEmpty && automatic.contains(kind),
                        interactive: kinds.count > 1
                    ) {
                        change { store.toggleMenuBarWindow(kind, for: provider) }
                    }
                    .help(QuotaWindowNames.name(kind, snapshot: provider == .claude ? state.snapshot : nil))
                }
            }
            .opacity(shown ? 1 : 0.35)
            .disabled(!shown)
            Spacer(minLength: 0)
        }
    }

    private var accountsRow: some View {
        let claudeShown = store.isInMenuBar(.claude)
        return HStack(alignment: .top, spacing: 8) {
            Text("settings.menu_bar.accounts".localized)
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 112, height: 28, alignment: .leading)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 18).padding(.top, 5)
            FlowLayout(spacing: 6) {
                ForEach(accounts.accounts) { account in
                    let today = account.isVisible(onWeekday: accounts.weekday)
                    let session = accounts.state(for: account).windows.first { $0.durationMinutes == 300 }
                    QuotaChip(
                        title: account.name.isEmpty ? "accounts.unnamed".localized : account.name,
                        detail: session.map { "\(Int($0.remainingPercentage.rounded()))%" }, account: account,
                        tint: account.tint.color, selected: account.showsInMenuBar
                    ) {
                        var edited = account
                        edited.showsInMenuBar.toggle()
                        change { accounts.update(edited) }
                    }
                    .opacity(today ? 1 : 0.45)
                    .help((today ? "settings.menu_bar.accounts_help" : "accounts.hidden_today").localized)
                }
            }
            .opacity(claudeShown ? 1 : 0.35)
            .disabled(!claudeShown)
        }
    }

    private func fallbackLabel(_ kind: QuotaWindowKind) -> String {
        switch kind {
        case .session: return "menu.label.session".localized
        case .weekly: return "menu.label.weekly".localized
        case .modelWeekly: return "settings.claude_model_placeholder".localized
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat.size").font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 20)
            Text("settings.menu_bar_size".localized).font(.callout)
            Spacer(minLength: 8)
            Text(store.menuBarSize.titleKey.localized)
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .contentTransition(.opacity)
            Slider(
                value: Binding(
                    get: { Double(Self.sizes.firstIndex(of: store.menuBarSize) ?? 1) },
                    set: { value in
                        let size = Self.sizes[min(max(Int(value.rounded()), 0), Self.sizes.count - 1)]
                        guard size != store.menuBarSize else { return }
                        change { store.menuBarSize = size }
                    }),
                in: 0...Double(Self.sizes.count - 1), step: 1
            ) {
                Text("settings.menu_bar_size".localized)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 170)
        }
        .frame(minHeight: 26)
    }
}

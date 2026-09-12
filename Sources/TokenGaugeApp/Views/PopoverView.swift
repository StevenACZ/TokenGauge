import AppKit
import SwiftUI
import TokenGaugeCore

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    let showSettings: () -> Void
    let showAbout: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @StateObject private var history: HistoryDashboardModel

    init(
        store: UsageStore, showSettings: @escaping () -> Void, showAbout: @escaping () -> Void,
        history: HistoryDashboardModel? = nil
    ) {
        self.store = store
        self.showSettings = showSettings
        self.showAbout = showAbout
        let preview = store.historyReadsEnabled ? nil : [store.claude.snapshot, store.codex.snapshot].compactMap { $0 }
        _history = StateObject(
            wrappedValue: history ?? HistoryDashboardModel(previewSnapshots: preview, mode: store.historyMode))
    }

    private var providerMaxHeight: CGFloat {
        let height: CGFloat =
            store.panelStyle == .rings
            ? Theme.Layout.ringProviderMaxHeight
            : store.panelStyle == .compact ? Theme.Layout.compactProviderMaxHeight : Theme.Layout.providerMaxHeight
        return height - (updates.phase == .idle ? 0 : 44)
    }

    private var panelWidth: CGFloat {
        let unified = store.displayMode == .unified
        switch store.panelStyle {
        case .standard: return unified ? Theme.Layout.unifiedPanelWidth : Theme.Layout.panelWidth
        case .compact: return unified ? Theme.Layout.compactUnifiedWidth : Theme.Layout.compactPanelWidth
        case .rings: return unified ? ringUnifiedWidth : Theme.Layout.ringPanelWidth
        }
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollIndicators(.automatic).frame(height: 500)
        }
        .frame(width: panelWidth)
        .frame(maxHeight: 500)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: "\(store.historyMode.rawValue):\(history.offset):\(store.historyRevision)") {
            let preview =
                store.historyReadsEnabled ? nil : [store.claude.snapshot, store.codex.snapshot].compactMap { $0 }
            await history.load(mode: store.historyMode, revision: store.historyRevision, previewSnapshots: preview)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            header
            providerPicker

            ViewThatFits(in: .vertical) {
                providerContent
                ScrollView {
                    providerContent
                }
                .scrollIndicators(.automatic)
                .frame(height: providerMaxHeight)
            }
            .frame(maxHeight: providerMaxHeight)
            .animation(store.animateChanges && !reduceMotion ? Theme.Motion.content : nil, value: store.panelStyle)
            HistoryPanelView(
                model: history, mode: $store.historyMode,
                providers: store.displayMode.providers, compact: store.panelStyle != .standard)
            if store.panelStyle == .standard {
                Divider().padding(.top, 1)
                footer
            } else if updates.phase != .idle {
                Divider()
                UpdateActionView().padding(5)
            }
        }
        .padding(.horizontal, Theme.Layout.panelPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: panelWidth)
        .environment(\.quotaAnimationsEnabled, store.animateChanges)
        .fixedSize(horizontal: false, vertical: true)
        .id(localization.language)
    }

    private var providerPicker: some View {
        HStack(spacing: 3) {
            ForEach(UsageDisplayMode.allCases) { mode in
                providerTab(mode)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("settings.display_mode".localized)
        .help("settings.display_mode_help".localized)
    }

    private func providerTab(_ mode: UsageDisplayMode) -> some View {
        let selected = store.displayMode == mode
        return Button {
            store.displayMode = mode
        } label: {
            HStack(spacing: 5) {
                if let provider = mode.singleProvider {
                    ProviderLogo(provider: provider, size: 12)
                } else {
                    Image(systemName: "square.grid.2x2.fill").font(.system(size: 11))
                }
                Text(mode.titleKey.localized).font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .primary : .secondary)
        .accessibilityIdentifier("TokenGauge.tab.\(mode.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var providerContent: some View {
        let layout =
            store.panelStyle == .compact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            ForEach(store.displayMode.providers, id: \.self) { provider in
                ProviderCard(
                    provider: provider, state: store.state(for: provider), panelStyle: store.panelStyle,
                    showProviderTitle: store.displayMode == .unified,
                    showLunaReserve: store.showLunaReserve,
                    hiddenClaudeWindows: store.hiddenClaudeWindows,
                    claudeMenuBarSource: store.claudeMenuBarSource,
                    claudeAutomaticRecovery: store.claudeAutomaticRecovery,
                    showHourlyPace: store.showHourlyPace,
                    paces: paces(for: provider)
                )
                .frame(width: ringCardWidth(for: provider))
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func paces(for provider: UsageProvider) -> [String: QuotaPace] {
        var result: [String: QuotaPace] = [:]
        for window in store.state(for: provider).snapshot?.windows ?? [] {
            result[window.id] = history.pace(provider: provider, window: window)
        }
        return result
    }

    private func ringWindowCount(_ provider: UsageProvider) -> CGFloat {
        let windows = store.state(for: provider).snapshot?.windows ?? []
        return CGFloat(
            max(
                1,
                WindowVisibility.visible(
                    windows, provider: provider, showLunaReserve: store.showLunaReserve,
                    hiddenClaudeWindows: store.hiddenClaudeWindows
                ).count))
    }

    private func minimumRingWidth(_ count: CGFloat) -> CGFloat {
        let cells = min(count, 3)
        return max(
            Theme.Layout.minimumRingCardWidth,
            cells * Theme.Layout.quotaRingCellWidth + (cells - 1) * Theme.Layout.quotaRingSpacing
                + Theme.Layout.cardPadding * 2)
    }

    private var ringUnifiedWidth: CGFloat {
        let content =
            minimumRingWidth(ringWindowCount(.codex)) + minimumRingWidth(ringWindowCount(.claude))
            + Theme.Layout.panelPadding * 2 + Theme.Layout.quotaRingSpacing
        return min(max(content, Theme.Layout.minimumRingUnifiedWidth), Theme.Layout.ringUnifiedWidth)
    }

    private func ringCardWidth(for provider: UsageProvider) -> CGFloat? {
        guard store.panelStyle == .rings, store.displayMode == .unified else { return nil }
        let available = ringUnifiedWidth - Theme.Layout.panelPadding * 2 - Theme.Layout.quotaRingSpacing
        let codexCount = ringWindowCount(.codex)
        let claudeCount = ringWindowCount(.claude)
        let minimumCodex = minimumRingWidth(codexCount)
        let minimumClaude = minimumRingWidth(claudeCount)
        let fitsOneRow = minimumCodex + minimumClaude <= available
        let lower = fitsOneRow ? minimumCodex : Theme.Layout.minimumRingCardWidth
        let upper = fitsOneRow ? available - minimumClaude : available - Theme.Layout.minimumRingCardWidth
        let codex = min(max(available * codexCount / (codexCount + claudeCount), lower), upper)
        return provider == .codex ? codex : available - codex
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            Text("app.name".localized)
                .font(.system(size: 14, weight: .semibold))

            Spacer(minLength: 0)

            Menu {
                Picker("settings.panel_style".localized, selection: $store.panelStyle) {
                    ForEach(QuotaPanelStyle.allCases) { style in
                        Label(style.titleKey.localized, systemImage: style.symbol).tag(style)
                    }
                }
            } label: {
                Image(systemName: store.panelStyle.symbol)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("settings.panel_style".localized)
            .accessibilityLabel("settings.panel_style".localized)
            .accessibilityIdentifier("TokenGauge.panelStyle")

            if store.panelStyle != .standard {
                Menu {
                    Button("settings.title".localized, action: showSettings)
                    Button("about.title".localized, action: showAbout)
                    Divider()
                    Button("action.quit".localized) { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("settings.title".localized)
            }

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
            .accessibilityLabel("action.refresh".localized)
            .disabled(store.isRefreshing)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if updates.phase != .idle {
                UpdateActionView().padding(5)
            }
            FooterActionRow(icon: "gearshape", title: "settings.title".localized, action: showSettings)
            FooterActionRow(icon: "info.circle", title: "about.title".localized, action: showAbout)
            FooterActionRow(icon: "power", title: "action.quit".localized) {
                NSApp.terminate(nil)
            }
        }
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
                if icon != "power" {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.rowRadius, style: .continuous)
                    .fill(hovered ? Color.primary.opacity(0.07) : Color.clear)
            )
            .foregroundStyle(icon == "power" ? Color.red : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("TokenGauge.footer.\(icon)")
        .onHover { hovered = $0 }
    }
}

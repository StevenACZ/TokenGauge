import AppKit
import SwiftUI
import TokenGaugeCore

struct MenuBarDesigner: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var demoStep = DemoStep.idle
    @State private var demoRun = 0

    private enum DemoStep: Int, Comparable {
        case idle, start, pointing, clicked, menu

        static func < (lhs: DemoStep, rhs: DemoStep) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private static let sizes: [MenuBarSize] = [.small, .medium, .large]
    private static let desktopHeight: CGFloat = 152
    private static let barHeight: CGFloat = 28
    private static let menuWidth: CGFloat = 188

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            desktop
            VStack(spacing: 8) {
                ForEach([UsageProvider.codex, .claude], id: \.self) { provider in
                    providerRow(provider)
                }
            }
            HStack(alignment: .top, spacing: 16) {
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
                sizeControl.frame(width: 200)
            }
        }
        .task(id: demoRun) {
            guard demoRun > 0 else { return }
            await playDemo()
        }
        .onAppear {
            if motion { demoRun += 1 }
        }
    }

    private var motion: Bool { store.animateChanges && !reduceMotion }

    private var appearance: NSAppearance {
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance
    }

    private var presentation: MenuBarPresentation {
        MenuBarPresentation(
            providers: store.displayMode.providers, state: { store.state(for: $0) }, appearance: appearance,
            size: store.menuBarSize, style: store.menuBarStyle, selection: store.menuBarSelections)
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

    private var desktop: some View {
        let current = presentation
        let key = "\(current.accessibilityLabel)|\(store.menuBarStyle)|\(store.menuBarSize)"
        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Theme.codex.opacity(0.75), Color.purple.opacity(0.45), Theme.claude.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "apple.logo").font(.system(size: 13, weight: .semibold))
                    Text("app.name".localized).font(.system(size: 13, weight: .bold))
                    ForEach([30, 38, 26], id: \.self) { width in
                        Capsule().fill(Color.primary.opacity(0.22)).frame(width: CGFloat(width), height: 6)
                    }
                    Spacer(minLength: 12)
                    ZStack {
                        Image(nsImage: current.renderedImage())
                            .id(key)
                            .transition(
                                motion ? .scale(scale: 0.82).combined(with: .opacity) : .opacity)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(demoStep >= .clicked ? 0.18 : 0))
                    )
                    .anchorPreference(key: IndicatorAnchorKey.self, value: .bounds) { $0 }
                    .animation(motion ? Theme.Motion.content : nil, value: key)
                    Group {
                        Image(systemName: "wifi")
                        Image(systemName: "battery.75percent")
                        Text(verbatim: "9:41").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.primary.opacity(0.75))
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .frame(height: Self.barHeight)
                .background(.ultraThinMaterial)
                Spacer(minLength: 0)
                rightClickHint
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlayPreferenceValue(IndicatorAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor { demoLayer(indicator: proxy[anchor], bounds: proxy.size) }
            }
        }
        .frame(height: Self.desktopHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(current.accessibilityLabel)
    }

    private var rightClickHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "contextualmenu.and.cursorarrow")
                .font(.system(size: 13, weight: .medium))
            Text("settings.right_click.hint".localized)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Button {
                demoRun += 1
            } label: {
                Label("settings.right_click.show".localized, systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .disabled(demoStep != .idle)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(.regularMaterial))
    }

    @ViewBuilder
    private func demoLayer(indicator: CGRect, bounds: CGSize) -> some View {
        let target = CGPoint(x: indicator.midX, y: indicator.midY + 3)
        let start = CGPoint(x: max(indicator.midX - 150, 40), y: bounds.height - 34)
        let menuX = min(max(indicator.minX, 8), bounds.width - Self.menuWidth - 8)
        ZStack(alignment: .topLeading) {
            if demoStep == .menu {
                quickMenuMock
                    .offset(x: menuX, y: indicator.maxY + 4)
                    .transition(
                        motion
                            ? .scale(scale: 0.92, anchor: .top).combined(with: .opacity) : .opacity)
            }
            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: 26, height: 26)
                .scaleEffect(demoStep >= .clicked ? 1.7 : 0.5)
                .opacity(demoStep == .pointing ? 0.9 : 0)
                .position(target)
            if demoStep >= .start, motion {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.black)
                    .shadow(color: .white, radius: 0.6)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .scaleEffect(demoStep == .clicked ? 0.85 : 1, anchor: .topLeading)
                    .position(demoStep >= .pointing ? CGPoint(x: target.x + 6, y: target.y + 8) : start)
                    .transition(.opacity)
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var quickMenuMock: some View {
        let provider = store.displayMode.providers.last ?? .claude
        return VStack(alignment: .leading, spacing: 1) {
            Text("provider.\(provider.rawValue)".localized)
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 1)
            mockRow("menu.quick.show_in_bar".localized, checked: true)
            Divider().padding(.vertical, 3)
            ForEach(QuotaMenuBarStyle.allCases) { style in
                mockRow(style.titleKey.localized, checked: store.menuBarStyle == style)
            }
        }
        .padding(.vertical, 6)
        .frame(width: Self.menuWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private func mockRow(_ title: String, checked: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                .opacity(checked ? 1 : 0)
            Text(title).font(.system(size: 11.5)).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 17)
    }

    private func playDemo() async {
        demoStep = .idle
        let animated = motion
        if animated {
            demoStep = .start
            guard await pause(0.12) else { return }
            withAnimation(.easeInOut(duration: 0.7)) { demoStep = .pointing }
            guard await pause(0.8) else { return }
            withAnimation(.easeOut(duration: 0.35)) { demoStep = .clicked }
            guard await pause(0.2) else { return }
        }
        withAnimation(animated ? .spring(response: 0.3, dampingFraction: 0.82) : .easeOut(duration: 0.2)) {
            demoStep = .menu
        }
        guard await pause(2.4) else { return }
        withAnimation(.easeOut(duration: 0.3)) { demoStep = .idle }
    }

    private func pause(_ seconds: Double) async -> Bool {
        (try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))) != nil
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

    private func fallbackLabel(_ kind: QuotaWindowKind) -> String {
        switch kind {
        case .session: return "menu.label.session".localized
        case .weekly: return "menu.label.weekly".localized
        case .modelWeekly: return "settings.claude_model_placeholder".localized
        }
    }

    private var sizeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("settings.menu_bar_size".localized).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(store.menuBarSize.titleKey.localized).font(.caption.weight(.semibold))
                    .contentTransition(.opacity)
            }
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
            } minimumValueLabel: {
                Image(systemName: "textformat.size.smaller").font(.system(size: 10))
            } maximumValueLabel: {
                Image(systemName: "textformat.size.larger").font(.system(size: 13))
            }
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.top, 4)
    }
}

private struct IndicatorAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

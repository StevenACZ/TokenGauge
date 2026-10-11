import AppKit
import SwiftUI
import TokenGaugeCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case menuBar, panel, accounts, general, about

    var id: String { rawValue }

    private var key: String {
        switch self {
        case .menuBar: "settings.menu_bar"
        case .panel: "settings.panel"
        case .accounts: "settings.accounts"
        case .general: "settings.general"
        case .about: "settings.about"
        }
    }

    var titleKey: String { self == .menuBar ? key + ".title" : key }
    var subtitleKey: String { key + ".subtitle" }

    var symbol: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .panel: "macwindow"
        case .accounts: "person.crop.circle"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var page = SettingsPage.menuBar
}

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var navigation: SettingsNavigation
    var accounts = ClaudeAccountsStore.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: SettingsPage?

    static let width: CGFloat = 820
    static let height: CGFloat = 680
    static let sidebarWidth: CGFloat = 204
    static let pagePadding: CGFloat = 26
    static let contentWidth = width - sidebarWidth - 1 - pagePadding * 2

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1).ignoresSafeArea()
            GeometryReader { proxy in
                ScrollView {
                    layout(height: proxy.size.height, titleBar: proxy.safeAreaInsets.top)
                        .id(navigation.page)
                        .transition(.opacity)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(width: Self.width)
        .frame(minHeight: 420, idealHeight: Self.height, maxHeight: .infinity)
        .onAppear { launchAtLogin.refresh() }
        .id(localization.language)
    }

    @ViewBuilder
    private func layout(height: CGFloat, titleBar: CGFloat) -> some View {
        if navigation.page == .about {
            page.frame(maxWidth: .infinity, minHeight: height).offset(y: -titleBar / 2)
        } else {
            page
                .padding(.horizontal, Self.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch navigation.page {
        case .menuBar: MenuBarDesigner(store: store, accounts: accounts)
        case .panel: SettingsPanelPage(store: store)
        case .accounts: SettingsAccountsPage(store: store, accounts: accounts)
        case .general: SettingsGeneralPage(store: store, launchAtLogin: launchAtLogin)
        case .about: AboutView()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text("settings.title".localized).font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
            ForEach(SettingsPage.allCases) { item in
                row(item)
            }
            Spacer(minLength: 12)
            Button {
                NSApp.terminate(nil)
            } label: {
                rowLabel("action.quit".localized, symbol: "power", selected: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("TokenGauge.settings.quit")
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(width: Self.sidebarWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035).ignoresSafeArea())
    }

    private func row(_ item: SettingsPage) -> some View {
        let selected = navigation.page == item
        return Button {
            withAnimation(store.animateChanges && !reduceMotion ? Theme.Motion.content : nil) {
                navigation.page = item
            }
        } label: {
            rowLabel(item.titleKey.localized, symbol: item.symbol, selected: selected)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            selected
                                ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovered == item ? 0.06 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? item : hovered == item ? nil : hovered }
        .accessibilityIdentifier("TokenGauge.settings.\(item.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func rowLabel(_ title: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 20)
            Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .contentShape(Rectangle())
    }
}

enum AppLinks {
    static let repository = URL(string: "https://github.com/StevenACZ/TokenGauge")!
    static let issues = repository.appendingPathComponent("issues")
    static let releases = repository.appendingPathComponent("releases")
    static let codexSetup = URL(string: "https://developers.openai.com/codex/cli/")!
    static let claudeSetup = URL(string: "https://code.claude.com/docs/en/quickstart")!
}

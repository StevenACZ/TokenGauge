import AppKit
import SwiftUI
import TokenGaugeCore

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    let showSettings: () -> Void
    let showAbout: () -> Void
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var localization = LocalizationManager.shared

    private var providerMaxHeight: CGFloat {
        Theme.Layout.providerMaxHeight - (updates.phase == .idle ? 0 : 44)
    }

    var body: some View {
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

    private var providerPicker: some View {
        HStack(spacing: 3) {
            providerTab(.codex, title: "provider.codex".localized)
            providerTab(.claude, title: "provider.claude".localized)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("settings.primary_provider".localized)
        .help("settings.primary_provider_help".localized)
    }

    private func providerTab(_ provider: UsageProvider, title: String) -> some View {
        let selected = store.primaryProvider == provider
        return Button {
            store.primaryProvider = provider
        } label: {
            HStack(spacing: 6) {
                ProviderLogo(provider: provider, size: 12)
                Text(title).font(.system(size: 11, weight: selected ? .semibold : .medium))
            }
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
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var secondaryProvider: UsageProvider {
        store.primaryProvider == .codex ? .claude : .codex
    }

    private var providerContent: some View {
        VStack(spacing: 8) {
            ProviderCard(provider: store.primaryProvider, state: store.state(for: store.primaryProvider))
            Button {
                store.primaryProvider = secondaryProvider
            } label: {
                ProviderCard(provider: secondaryProvider, state: store.state(for: secondaryProvider), compact: true)
            }
            .buttonStyle(.plain)
            .help("settings.switch_provider".localized)
        }
        .fixedSize(horizontal: false, vertical: true)
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
        .onHover { hovered = $0 }
    }
}

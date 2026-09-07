import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var updates = UpdateManager.shared

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "v\(version) · \(build)"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).frame(width: 88, height: 88)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("TokenGauge").font(.system(size: 28, weight: .bold, design: .rounded))
                Text(version).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            }
            if updates.available {
                UpdateActionView().frame(maxWidth: 300)
            } else {
                Text("updates.development".localized).font(.caption).foregroundStyle(.secondary)
            }
            Text("about.description".localized)
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                badge("about.local".localized, icon: "chart.bar")
                badge("about.private".localized, icon: "lock.fill")
            }
            Divider()
            HStack(spacing: 14) {
                Link(destination: AppLinks.repository) { Label("GitHub", systemImage: "link") }
                Link(destination: AppLinks.issues) {
                    Label("about.report".localized, systemImage: "ladybug")
                }
            }.buttonStyle(.bordered)
            Link("about.releases".localized, destination: AppLinks.releases).font(.caption)
            VStack(spacing: 4) {
                Text("about.made".localized)
                Text("© 2026 StevenACZ")
            }.font(.caption).foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .id(localization.language)
    }

    private func badge(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(Theme.codex)
            .background(Capsule().fill(Theme.codex.opacity(0.1)))
            .overlay(Capsule().strokeBorder(Theme.codex.opacity(0.2)))
    }
}

struct UpdateActionView: View {
    @ObservedObject private var updates = UpdateManager.shared

    var body: some View {
        Group {
            switch updates.phase {
            case .idle:
                switch updates.manualCheckStatus {
                case .checking:
                    Label("updates.checking".localized, systemImage: "clock")
                case .upToDate:
                    Label("updates.current".localized, systemImage: "checkmark.circle")
                case .failed:
                    Button("updates.check_failed".localized) { updates.checkForUpdatesManually() }
                case .idle:
                    Button("updates.check".localized) { updates.checkForUpdatesManually() }
                }
            case .available(let version):
                Button("updates.install".localized(version)) { updates.installPendingUpdate() }
            case .downloading(let fraction):
                VStack(alignment: .leading, spacing: 5) {
                    Text("updates.downloading".localized)
                    if let fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            case .installing:
                Label("updates.installing".localized, systemImage: "arrow.down.circle")
            case .failed:
                Button("updates.retry".localized) { updates.installPendingUpdate() }
            }
        }.font(.callout).frame(maxWidth: .infinity, alignment: .center)
    }
}

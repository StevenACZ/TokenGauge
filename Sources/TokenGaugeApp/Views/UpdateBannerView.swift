import SwiftUI

struct UpdateBannerView: View {
    @ObservedObject var updates: UpdateManager
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let compactHeight: CGFloat = 38
    static let progressHeight: CGFloat = 46
    static let cornerRadius: CGFloat = 9

    init(updates: UpdateManager = .shared) {
        self.updates = updates
    }

    static func height(for phase: UpdateManager.Phase) -> CGFloat {
        switch phase {
        case .idle: return 0
        case .downloading, .extracting: return progressHeight
        case .checking, .available, .readyToInstall, .installing, .failed: return compactHeight
        }
    }

    var body: some View {
        Group {
            switch updates.phase {
            case .idle:
                EmptyView()
            case .checking:
                row(title: "updates.checking".localized, icon: "arrow.triangle.2.circlepath")
            case .available(let version):
                row(title: "updates.banner_available".localized(version), icon: "arrow.down.circle.fill") {
                    action("updates.download".localized) { updates.installPendingUpdate() }
                }
            case .downloading(let version, let fraction):
                progress(
                    title: text(
                        "updates.banner_downloading", pending: "updates.banner_downloading_pending",
                        version: version, fraction: fraction),
                    fraction: fraction)
            case .extracting(let version, let fraction):
                progress(
                    title: text(
                        "updates.banner_extracting", pending: "updates.banner_extracting_pending",
                        version: version, fraction: fraction),
                    fraction: fraction)
            case .readyToInstall(let version, let deferred):
                if deferred {
                    row(title: "updates.banner_ready".localized(version), icon: "arrow.down.circle.fill") {
                        action("updates.install_now".localized) { updates.resumeDeferredInstall() }
                    }
                } else {
                    row(title: "updates.banner_ready".localized(version), icon: "arrow.down.circle.fill") {
                        HStack(spacing: 6) {
                            action("updates.install_now".localized) { updates.installReadyUpdate() }
                            Button("updates.later".localized) { updates.deferReadyUpdate() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            case .installing:
                row(title: "updates.installing".localized, icon: "arrow.down.circle.fill")
            case .failed(let message):
                row(title: message.localized, icon: "exclamationmark.triangle.fill") {
                    action("updates.retry_action".localized) { updates.installPendingUpdate() }
                }
            }
        }
        .id(localization.language)
    }

    private func row(title: String, icon: String) -> some View {
        row(title: title, icon: icon) { EmptyView() }
    }

    private func row(
        title: String,
        icon: String,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            trailing()
        }
        .frame(height: Self.compactHeight)
        .modifier(BannerChrome())
    }

    private func progress(title: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            UpdateProgressBar(fraction: fraction, reduceMotion: reduceMotion)
        }
        .frame(height: Self.progressHeight)
        .modifier(BannerChrome())
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
    }

    private func text(_ key: String, pending: String, version: String, fraction: Double?) -> String {
        guard let fraction else { return pending.localized(version) }
        return key.localized(version, Int((fraction * 100).rounded()))
    }
}

private struct BannerChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UpdateBannerView.cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
    }
}

private struct UpdateProgressBar: View {
    let fraction: Double?
    let reduceMotion: Bool

    @State private var sliding = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                if let fraction {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, min(1, fraction)) * geometry.size.width)
                        .animation(reduceMotion ? nil : .linear(duration: 0.2), value: fraction)
                } else if reduceMotion {
                    Capsule().fill(Color.accentColor.opacity(0.35))
                } else {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * 0.3)
                        .offset(x: sliding ? geometry.size.width * 0.7 : 0)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                sliding = true
                            }
                        }
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

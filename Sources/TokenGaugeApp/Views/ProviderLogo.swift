import AppKit
import SwiftUI
import TokenGaugeCore

struct ProviderLogo: View {
    let provider: UsageProvider
    let size: CGFloat

    var body: some View {
        Group {
            if let image = ProviderLogoAssets.image(for: provider) {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: provider == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(provider == .claude ? Theme.claude : Theme.codex)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

@MainActor
private enum ProviderLogoAssets {
    static func image(for provider: UsageProvider) -> NSImage? {
        provider == .claude ? claude : codex
    }

    private static let claude = load("provider-claude")
    private static let codex = load("provider-codex")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
            let image = NSImage(contentsOf: url)
        else { return nil }
        image.size = NSSize(width: 128, height: 128)
        return image
    }
}

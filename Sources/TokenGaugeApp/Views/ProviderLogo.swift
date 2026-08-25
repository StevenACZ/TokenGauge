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
enum ProviderLogoAssets {
    static func image(for provider: UsageProvider) -> NSImage? {
        provider == .claude ? claude : codex
    }

    static func menuBarImage(for provider: UsageProvider, size: CGFloat) -> NSImage? {
        guard let source = image(for: provider), let copy = source.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: size, height: size)
        copy.isTemplate = false
        return copy
    }

    static let claude = load("provider-claude")
    static let codex = load("provider-codex")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
            let image = NSImage(contentsOf: url)
        else { return nil }
        image.size = NSSize(width: 128, height: 128)
        return image
    }
}

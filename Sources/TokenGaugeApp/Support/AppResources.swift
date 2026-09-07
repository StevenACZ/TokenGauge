import Foundation

enum AppResources {
    private static let resourceBundleName = "TokenGauge_TokenGaugeApp.bundle"

    static let bundle = resolve(in: Bundle.main) {
        adjacentBundle(to: [Bundle.main, Bundle(for: ResourceBundleMarker.self)]) ?? Bundle.main
    }

    static func resolve(in main: Bundle, fallback: () -> Bundle) -> Bundle {
        if let resources = main.resourceURL {
            let packaged = resources.appendingPathComponent(resourceBundleName)
            if let bundle = Bundle(url: packaged) { return bundle }
            if main.url(forResource: "provider-codex", withExtension: "svg") != nil {
                return main
            }
        }
        return fallback()
    }

    static func adjacentBundle(to bundles: [Bundle]) -> Bundle? {
        for bundle in bundles {
            let roots = [
                bundle.bundleURL,
                bundle.bundleURL.deletingLastPathComponent(),
                bundle.executableURL?.deletingLastPathComponent(),
            ].compactMap { $0 }
            for root in roots {
                if let resources = Bundle(url: root.appendingPathComponent(resourceBundleName)) {
                    return resources
                }
            }
        }
        return nil
    }
}

private final class ResourceBundleMarker: NSObject {}

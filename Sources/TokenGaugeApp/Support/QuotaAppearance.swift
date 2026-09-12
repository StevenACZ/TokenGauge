import SwiftUI

enum QuotaPanelStyle: String, CaseIterable, Identifiable {
    case standard
    case compact
    case rings

    var id: String { rawValue }
    var titleKey: String { "settings.panel_style." + rawValue }
    var symbol: String {
        switch self {
        case .standard: "rectangle.split.1x2"
        case .compact: "list.bullet"
        case .rings: "circle.circle"
        }
    }
}

enum QuotaMenuBarStyle: String, CaseIterable, Identifiable {
    case numbers
    case bars
    case rings

    var id: String { rawValue }
    var titleKey: String { "settings.indicator_style." + rawValue }
}

private struct QuotaAnimationsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var quotaAnimationsEnabled: Bool {
        get { self[QuotaAnimationsKey.self] }
        set { self[QuotaAnimationsKey.self] = newValue }
    }
}

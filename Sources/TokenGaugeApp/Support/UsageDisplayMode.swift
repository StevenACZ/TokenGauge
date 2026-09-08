import TokenGaugeCore

enum UsageDisplayMode: String, CaseIterable, Identifiable {
    case codex
    case claude
    case unified

    var id: String { rawValue }

    var providers: [UsageProvider] {
        switch self {
        case .codex: return [.codex]
        case .claude: return [.claude]
        case .unified: return [.codex, .claude]
        }
    }

    var singleProvider: UsageProvider? {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .unified: return nil
        }
    }

    var titleKey: String {
        switch self {
        case .codex: return "provider.codex"
        case .claude: return "provider.claude_short"
        case .unified: return "view.unified"
        }
    }
}

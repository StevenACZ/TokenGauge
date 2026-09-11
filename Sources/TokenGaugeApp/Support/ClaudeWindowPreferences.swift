import TokenGaugeCore

enum ClaudeWindowKind: String, CaseIterable, Identifiable, Codable {
    case session
    case weekly
    case modelWeekly

    var id: String { rawValue }

    static func of(_ window: QuotaWindow) -> ClaudeWindowKind? {
        switch window.durationMinutes {
        case 300: return .session
        case 10_080: return (window.displayName ?? "").isEmpty ? .weekly : .modelWeekly
        default: return nil
        }
    }

    static func decode(_ rawValues: [String]?) -> Set<ClaudeWindowKind> {
        Set((rawValues ?? []).compactMap(ClaudeWindowKind.init(rawValue:)))
    }
}

enum ClaudeMenuBarSource: String, CaseIterable, Identifiable {
    case automatic
    case session
    case weekly
    case modelWeekly

    var id: String { rawValue }

    var kind: ClaudeWindowKind? {
        switch self {
        case .automatic: return nil
        case .session: return .session
        case .weekly: return .weekly
        case .modelWeekly: return .modelWeekly
        }
    }
}

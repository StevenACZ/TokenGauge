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

    static func ordered(_ kinds: Set<ClaudeWindowKind>) -> [ClaudeWindowKind] {
        allCases.filter(kinds.contains)
    }
}

@MainActor
enum ClaudeWindowNames {
    static func name(_ kind: ClaudeWindowKind, snapshot: ProviderUsageSnapshot?) -> String {
        switch kind {
        case .session: return "window.session".localized
        case .weekly: return "window.weekly".localized
        case .modelWeekly:
            let scoped = snapshot?.windows.first { ClaudeWindowKind.of($0) == .modelWeekly }
            return "window.model_weekly".localized(
                scoped?.displayName ?? "settings.claude_model_placeholder".localized)
        }
    }
}

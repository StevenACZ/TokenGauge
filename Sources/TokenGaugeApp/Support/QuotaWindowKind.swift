import TokenGaugeCore

enum QuotaWindowKind: String, CaseIterable, Identifiable, Codable {
    case session
    case weekly
    case modelWeekly

    var id: String { rawValue }

    static func of(_ window: QuotaWindow) -> QuotaWindowKind? {
        switch window.durationMinutes {
        case 300: return .session
        case 10_080: return (window.displayName ?? "").isEmpty ? .weekly : .modelWeekly
        default: return nil
        }
    }

    static func of(_ window: QuotaWindow, provider: UsageProvider) -> QuotaWindowKind? {
        guard provider == .codex else { return of(window) }
        switch window.durationMinutes {
        case 300: return .session
        case 10_080: return .weekly
        default: return nil
        }
    }

    static func decode(_ rawValues: [String]?) -> Set<QuotaWindowKind> {
        Set((rawValues ?? []).compactMap(QuotaWindowKind.init(rawValue:)))
    }

    static func ordered(_ kinds: Set<QuotaWindowKind>) -> [QuotaWindowKind] {
        allCases.filter(kinds.contains)
    }
}

@MainActor
enum QuotaWindowNames {
    static func name(_ kind: QuotaWindowKind, snapshot: ProviderUsageSnapshot?) -> String {
        switch kind {
        case .session: return "window.session".localized
        case .weekly: return "window.weekly".localized
        case .modelWeekly:
            let scoped = snapshot?.windows.first { QuotaWindowKind.of($0) == .modelWeekly }
            return "window.model_weekly".localized(
                scoped?.displayName ?? "settings.claude_model_placeholder".localized)
        }
    }
}

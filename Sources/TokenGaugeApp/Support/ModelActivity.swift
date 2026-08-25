import Foundation
import TokenGaugeCore

struct ModelUsageChip: Equatable, Identifiable {
    let model: String
    let tokens: Int

    var id: String { model }
    @MainActor var displayName: String { ModelActivity.displayName(model) }
}

@MainActor
enum ModelActivity {
    static func chips(
        buckets: [ModelTokenBucket],
        since: Date?,
        limit: Int = 3
    ) -> [ModelUsageChip] {
        ModelTokenAggregator.byModel(buckets, since: since)
            .prefix(limit)
            .map { ModelUsageChip(model: $0.model, tokens: $0.tokens) }
    }

    static func displayName(_ raw: String) -> String {
        let identifier = raw.lowercased()
        for (needle, label) in knownFamilies where identifier.contains(needle) {
            return label
        }
        if identifier == "unknown" { return "model.unknown".localized }
        return raw
    }

    private static let knownFamilies: [(String, String)] = [
        ("fable", "Fable"),
        ("opus", "Opus"),
        ("sonnet", "Sonnet"),
        ("haiku", "Haiku"),
    ]
}

enum WindowVisibility {
    static func visible(_ windows: [QuotaWindow], provider: UsageProvider) -> [QuotaWindow] {
        switch provider {
        case .claude:
            return windows
        case .codex:
            let mainline = windows.filter { !isSpark($0) }
            let weekly = mainline.filter { $0.durationMinutes == weeklyMinutes }
            return weekly.isEmpty ? mainline : weekly
        }
    }

    private static let weeklyMinutes = 10_080

    private static func isSpark(_ window: QuotaWindow) -> Bool {
        let haystack = "\(window.displayName ?? "") \(window.id)".lowercased()
        return haystack.contains("spark")
    }
}

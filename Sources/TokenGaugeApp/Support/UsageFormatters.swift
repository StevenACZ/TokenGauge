import Foundation
import TokenGaugeCore

enum UsageFormatters {
    static func percentage(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func tokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        if value >= 1_000_000_000 {
            return "\(decimal(Double(value) / 1_000_000_000))B"
        }
        if value >= 1_000_000 {
            return "\(decimal(Double(value) / 1_000_000))M"
        }
        if value >= 1_000 {
            return "\(decimal(Double(value) / 1_000))K"
        }
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    @MainActor static func resetCompact(_ date: Date?) -> String {
        guard let date else { return "reset.unknown_short".localized }
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "reset.pending_short".localized }
        let formatter = DateComponentsFormatter()
        formatter.calendar?.locale = Locale(identifier: LocalizationManager.shared.language.rawValue)
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = remaining >= 86_400 ? [.day] : (remaining >= 3600 ? [.hour] : [.minute])
        return formatter.string(from: max(remaining, 60)) ?? "reset.unknown_short".localized
    }

    @MainActor static func lastUpdated(_ date: Date?) -> String {
        guard let date else { return "updated.never".localized }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: LocalizationManager.shared.language.rawValue)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @MainActor static func windowName(_ window: QuotaWindow) -> String {
        if window.id == "five_hour" || window.durationMinutes == 300 {
            return "window.session".localized
        }
        if window.id == "seven_day" || window.durationMinutes == 10_080 {
            return "window.weekly".localized
        }
        if window.id.hasPrefix("seven_day_") {
            let model = window.id.replacingOccurrences(of: "seven_day_", with: "").capitalized
            return "window.model_weekly".localized(model)
        }
        if let displayName = window.displayName, !displayName.isEmpty {
            return displayName
        }
        return "window.usage".localized
    }

    @MainActor static func modelChips(_ chips: [ModelUsageChip]) -> String? {
        guard !chips.isEmpty else { return nil }
        return chips.map { "\($0.displayName) \(tokens($0.tokens))" }.joined(separator: " · ")
    }

    private static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = value < 10 ? 1 : 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

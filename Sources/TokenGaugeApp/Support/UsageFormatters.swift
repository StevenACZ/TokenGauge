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

    @MainActor static func reset(_ date: Date?) -> String {
        guard let date else { return "reset.unknown".localized }
        if date <= Date() { return "reset.pending_refresh".localized }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: LocalizationManager.shared.language.rawValue)
        formatter.unitsStyle = .full
        return "reset.in".localized(formatter.localizedString(for: date, relativeTo: Date()))
    }

    @MainActor static func lastUpdated(_ date: Date?) -> String {
        guard let date else { return "updated.never".localized }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: LocalizationManager.shared.language.rawValue)
        formatter.unitsStyle = .short
        return "updated.value".localized(formatter.localizedString(for: date, relativeTo: Date()))
    }

    @MainActor static func windowName(_ window: QuotaWindow) -> String {
        if let displayName = window.displayName, !displayName.isEmpty {
            if window.durationMinutes == 300 {
                return "window.named_session".localized(displayName)
            }
            if window.durationMinutes == 10_080 {
                return "window.named_weekly".localized(displayName)
            }
            return displayName
        }
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
        if window.id.contains("other") {
            return "window.other_models".localized
        }
        return "window.usage".localized
    }

    private static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = value < 10 ? 1 : 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

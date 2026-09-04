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

    @MainActor static func reset(
        _ date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else { return "reset.unknown".localized }
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else { return "reset.pending".localized }

        if remaining < 86_400 {
            let units: NSCalendar.Unit = remaining < 3_600 ? [.minute] : [.hour]
            guard let span = span(remaining, units: units) else { return "reset.unknown".localized }
            return "reset.in_at".localized(span, clock(date))
        }

        let dayDelta =
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: date)
            ).day ?? 0
        if dayDelta == 1 {
            return "reset.tomorrow_at".localized(clock(date))
        }

        let days = max(1, Int((remaining / 86_400).rounded()))
        guard let span = span(Double(days) * 86_400, units: [.day]) else { return "reset.unknown".localized }
        return "reset.in".localized(span)
    }

    @MainActor private static func span(_ interval: TimeInterval, units: NSCalendar.Unit) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.calendar?.locale = Locale(identifier: LocalizationManager.shared.language.rawValue)
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = units
        return formatter.string(from: max(interval, 60))
    }

    @MainActor private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: LocalizationManager.shared.language.rawValue)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @MainActor static func resetCredits(_ count: Int) -> String {
        count == 1 ? "reset_credits.one".localized : "reset_credits.many".localized(count)
    }

    @MainActor static func lastUpdated(_ date: Date?) -> String {
        guard let date else { return "updated.never".localized }
        let age = Date().timeIntervalSince(date)
        guard age >= 10 else { return "updated.now".localized }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: LocalizationManager.shared.language.rawValue)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @MainActor static func windowName(_ window: QuotaWindow) -> String {
        if isReserve(window) && window.durationMinutes == 10_080 {
            return "window.reserve_weekly".localized
        }
        if window.id.hasPrefix("codex.") && window.durationMinutes == 10_080 {
            return "window.general_weekly".localized
        }
        if window.id == "five_hour" || window.durationMinutes == 300 {
            return "window.session".localized
        }
        if let displayName = window.displayName, !displayName.isEmpty, window.durationMinutes == 10_080 {
            return "window.model_weekly".localized(displayName)
        }
        if window.id == "seven_day" || window.durationMinutes == 10_080 {
            return "window.weekly".localized
        }
        if let displayName = window.displayName, !displayName.isEmpty {
            return displayName
        }
        return "window.usage".localized
    }

    private static func isReserve(_ window: QuotaWindow) -> Bool {
        window.id.hasPrefix("base_model_inference.") || window.displayName?.lowercased() == "gpt-reserve"
    }

    @MainActor static func windowHelp(_ window: QuotaWindow) -> String {
        isReserve(window) ? "window.reserve_help".localized : windowName(window)
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

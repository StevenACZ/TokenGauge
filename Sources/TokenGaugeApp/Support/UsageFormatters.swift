import Foundation
import TokenGaugeCore

enum UsageFormatters {
    private static let integer = IntegerFormatStyle<Int>.number
    private static let smallDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
    private static let largeDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))

    static func percentage(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "\(Int(seconds.rounded())) s" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 48 { return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min" }
        return "\(hours / 24) d \(hours % 24) h"
    }

    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000_000 {
            return "\(decimal(Double(value) / 1_000_000_000))B"
        }
        if value >= 1_000_000 {
            return "\(decimal(Double(value) / 1_000_000))M"
        }
        if value >= 1_000 {
            return "\(decimal(Double(value) / 1_000))K"
        }
        return value.formatted(integer)
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
        let formatter = LocalizedFormatters.current.span
        formatter.allowedUnits = units
        return formatter.string(from: max(interval, 60))
    }

    @MainActor private static func clock(_ date: Date) -> String {
        LocalizedFormatters.current.clock.string(from: date)
    }

    @MainActor static func resetCredits(_ count: Int) -> String {
        count == 1 ? "reset_credits.one".localized : "reset_credits.many".localized(count)
    }

    @MainActor static func resetCreditsAvailable(_ count: Int) -> String {
        count == 1 ? "reset_credits.available_one".localized : "reset_credits.available_many".localized(count)
    }

    @MainActor static func lastUpdated(_ date: Date?) -> String {
        guard let date else { return "updated.never".localized }
        let age = Date().timeIntervalSince(date)
        guard age >= 10 else { return "updated.now".localized }
        return LocalizedFormatters.current.relative.localizedString(for: date, relativeTo: Date())
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
        value.formatted(value < 10 ? smallDecimal : largeDecimal)
    }
}

@MainActor
private struct LocalizedFormatters {
    let span: DateComponentsFormatter
    let clock: DateFormatter
    let relative: RelativeDateTimeFormatter

    private static var cache: [AppLanguage: LocalizedFormatters] = [:]

    static var current: LocalizedFormatters {
        let language = LocalizationManager.shared.language
        if let formatters = cache[language] { return formatters }
        let formatters = LocalizedFormatters(locale: Locale(identifier: language.rawValue))
        cache[language] = formatters
        return formatters
    }

    private init(locale: Locale) {
        span = DateComponentsFormatter()
        span.calendar?.locale = locale
        span.unitsStyle = .abbreviated
        span.maximumUnitCount = 1
        clock = DateFormatter()
        clock.locale = locale
        clock.dateStyle = .none
        clock.timeStyle = .short
        relative = RelativeDateTimeFormatter()
        relative.locale = locale
        relative.unitsStyle = .short
    }
}

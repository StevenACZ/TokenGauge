import Foundation
import TokenGaugeCore

struct HistoryReset: Identifiable, Equatable {
    let provider: UsageProvider
    let date: Date
    var isProjected = false
    var id: String { provider.rawValue + ":" + String(date.timeIntervalSince1970) }

    static func upcoming(
        provider: UsageProvider, windows: [QuotaWindow], now: Date = Date(), through end: Date? = nil
    ) -> [Self] {
        let end = end ?? now.addingTimeInterval(366 * 86400)
        let dates = windows.compactMap { window -> Date? in
            guard window.durationMinutes == 10080, let date = window.resetsAt, date > now else { return nil }
            return date
        }.sorted()
        var result: [Self] = []
        for start in dates {
            var date = start
            while date <= max(end, start) {
                if let index = result.firstIndex(where: { abs($0.date.timeIntervalSince(date)) < 60 }) {
                    if date == start { result[index].isProjected = false }
                } else {
                    result.append(Self(provider: provider, date: date, isProjected: date != start))
                }
                date = date.addingTimeInterval(7 * 86400)
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    @MainActor var label: String {
        let locale = Locale(identifier: LocalizationManager.shared.language.rawValue)
        let name = (provider == .codex ? "provider.codex" : "provider.claude_short").localized
        return name + " · " + date.formatted(.dateTime.hour().minute().locale(locale))
    }
}

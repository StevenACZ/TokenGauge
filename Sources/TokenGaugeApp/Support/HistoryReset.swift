import Foundation
import TokenGaugeCore

struct HistoryReset: Identifiable, Equatable {
    let provider: UsageProvider
    let window: QuotaWindow
    let date: Date
    var id: String { provider.rawValue + ":" + window.id }

    static func upcoming(provider: UsageProvider, windows: [QuotaWindow], now: Date = Date()) -> [Self] {
        windows.compactMap { window in
            guard window.durationMinutes == 10080, let date = window.resetsAt, date > now else { return nil }
            return Self(provider: provider, window: window, date: date)
        }.sorted { $0.date < $1.date }
    }

    @MainActor var label: String {
        let locale = Locale(identifier: LocalizationManager.shared.language.rawValue)
        let name = (provider == .codex ? "provider.codex" : "provider.claude_short").localized
        return name + " · " + UsageFormatters.windowName(window) + " · "
            + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(locale))
    }
}

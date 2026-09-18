import Foundation
import TokenGaugeCore

struct AppPreferences {
    enum Key {
        static let primaryProvider = "primaryProvider"
        static let displayMode = "displayMode"
        static let menuBarSize = "menuBarSize"
        static let quotaPanelStyle = "quotaPanelStyle"
        static let quotaMenuBarStyle = "quotaMenuBarStyle"
        static let quotaAnimateChanges = "quotaAnimateChanges"
        static let historyMode = "historyMode"
        static let showHourlyPace = "showHourlyPace"
        static let showLunaReserve = "showLunaReserve"
        static let hiddenClaudeWindows = "hiddenClaudeWindows"
        static let claudeMenuBarSource = "claudeMenuBarSource"
        static let claudeAutomaticRecovery = "claudeAutomaticRecovery"
        static let claudeRecoveryNextAttempt = "claudeRecoveryNextAttempt"
        static let claudeRecoveryFailures = "claudeRecoveryFailures"
        static let appLanguage = "appLanguage"
        static let codexExecutablePath = "codexExecutablePath"

        static func cancelledAt(_ provider: UsageProvider) -> String {
            "\(provider.rawValue)CancelledAt"
        }

        static func cancellationDailyBaseline(_ provider: UsageProvider) -> String {
            "\(provider.rawValue)CancellationDailyBaseline"
        }
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var primaryProvider: UsageProvider {
        get { value(Key.primaryProvider) ?? .codex }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.primaryProvider) }
    }

    var displayMode: UsageDisplayMode {
        get {
            let provider = primaryProvider
            return UsageDisplayMode(rawValue: defaults.string(forKey: Key.displayMode) ?? provider.rawValue)
                ?? (provider == .codex ? .codex : .claude)
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.displayMode) }
    }

    var menuBarSize: MenuBarSize {
        get { value(Key.menuBarSize) ?? .large }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.menuBarSize) }
    }

    var panelStyle: QuotaPanelStyle {
        get { value(Key.quotaPanelStyle) ?? .standard }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.quotaPanelStyle) }
    }

    var menuBarStyle: QuotaMenuBarStyle {
        get { value(Key.quotaMenuBarStyle) ?? .numbers }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.quotaMenuBarStyle) }
    }

    var animateChanges: Bool {
        get { bool(Key.quotaAnimateChanges, default: true) }
        nonmutating set { defaults.set(newValue, forKey: Key.quotaAnimateChanges) }
    }

    var historyMode: HistoryMode {
        get { value(Key.historyMode) ?? .recent }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.historyMode) }
    }

    var showHourlyPace: Bool {
        get { bool(Key.showHourlyPace, default: true) }
        nonmutating set { defaults.set(newValue, forKey: Key.showHourlyPace) }
    }

    var showLunaReserve: Bool {
        get { bool(Key.showLunaReserve, default: true) }
        nonmutating set { defaults.set(newValue, forKey: Key.showLunaReserve) }
    }

    var hiddenClaudeWindows: Set<ClaudeWindowKind> {
        get { ClaudeWindowKind.decode(defaults.stringArray(forKey: Key.hiddenClaudeWindows)) }
        nonmutating set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.hiddenClaudeWindows) }
    }

    var claudeMenuBarSource: ClaudeMenuBarSource {
        get { value(Key.claudeMenuBarSource) ?? .automatic }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.claudeMenuBarSource) }
    }

    var claudeAutomaticRecovery: Bool {
        get { bool(Key.claudeAutomaticRecovery, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.claudeAutomaticRecovery) }
    }

    var claudeAutomaticRecoveryDecided: Bool {
        defaults.object(forKey: Key.claudeAutomaticRecovery) != nil
    }

    var claudeRecoveryNextAttempt: Date? {
        get { defaults.object(forKey: Key.claudeRecoveryNextAttempt) as? Date }
        nonmutating set { replace(newValue, forKey: Key.claudeRecoveryNextAttempt) }
    }

    var claudeRecoveryFailures: Int {
        get { defaults.integer(forKey: Key.claudeRecoveryFailures) }
        nonmutating set { defaults.set(newValue, forKey: Key.claudeRecoveryFailures) }
    }

    func cancelledAt(_ provider: UsageProvider) -> Date? {
        defaults.object(forKey: Key.cancelledAt(provider)) as? Date
    }

    func setCancelledAt(_ date: Date?, for provider: UsageProvider) {
        replace(date, forKey: Key.cancelledAt(provider))
    }

    func cancellationDailyBaseline(_ provider: UsageProvider) -> [String: Int]? {
        defaults.dictionary(forKey: Key.cancellationDailyBaseline(provider)) as? [String: Int]
    }

    func setCancellationDailyBaseline(_ totals: [String: Int]?, for provider: UsageProvider) {
        replace(totals, forKey: Key.cancellationDailyBaseline(provider))
    }

    private func value<Value: RawRepresentable>(_ key: String) -> Value? where Value.RawValue == String {
        defaults.string(forKey: key).flatMap(Value.init(rawValue:))
    }

    private func bool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private func replace(_ value: Any?, forKey key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

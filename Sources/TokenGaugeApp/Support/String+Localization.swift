import Foundation

extension String {
    @MainActor var localized: String {
        LocalizationManager.shared.text(self)
    }

    @MainActor func localized(_ arguments: CVarArg...) -> String {
        String(
            format: localized,
            locale: Locale(identifier: LocalizationManager.shared.language.rawValue),
            arguments: arguments
        )
    }
}

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }

    static func preferred(from languages: [String]) -> AppLanguage {
        for language in languages {
            let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
            if let code, let supported = AppLanguage(rawValue: code) { return supported }
        }
        return .english
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            bundle = Self.bundle(for: language)
        }
    }

    @Published private(set) var bundle: Bundle

    private init() {
        let stored = UserDefaults.standard.string(forKey: "appLanguage")
        let language = AppLanguage(rawValue: stored ?? "") ?? AppLanguage.preferred(from: Locale.preferredLanguages)
        self.language = language
        bundle = Self.bundle(for: language)
    }

    func text(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let path = AppResources.bundle.path(forResource: language.rawValue, ofType: "lproj") else {
            return AppResources.bundle
        }
        return Bundle(path: path) ?? AppResources.bundle
    }
}

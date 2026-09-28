import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    public static let preferenceKey = "disklens.language"
    public static var saved: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system
    }
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: L10n.string("跟随系统")
        case .chinese: "简体中文"
        case .english: "English"
        }
    }
    public var badge: String {
        switch self {
        case .system: L10n.string("自动")
        case .chinese: "中"
        case .english: "EN"
        }
    }
    public var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .chinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }
}

public enum L10n {
    private static let englishBundle = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap { Bundle(path: $0) }
    private static let chineseBundle = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap { Bundle(path: $0) }

    public static func string(_ key: String, language: AppLanguage = .saved) -> String {
        let bundle: Bundle?
        switch language {
        case .system: bundle = Bundle.main
        case .chinese: bundle = chineseBundle
        case .english: bundle = englishBundle
        }
        return bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: AppLanguage.saved.locale, arguments: arguments)
    }
}

import Foundation

/// Resolves Russian or English UI strings with English fallback for other system languages.
public func tr(_ key: String) -> String {
    let language = Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
    guard let path = Bundle.module.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

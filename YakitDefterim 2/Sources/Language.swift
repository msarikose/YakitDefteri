import Foundation

// Keeps stored category keys and user-entered content unchanged.
@MainActor func localized(_ key: String) -> String {
    let language = Store.shared.db.language ?? "tr"
    guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

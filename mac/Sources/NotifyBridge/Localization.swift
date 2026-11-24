import Foundation

/// Looks a user-visible string up in Localizable.strings. The Turkish text is the key, English lives in en.lproj.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

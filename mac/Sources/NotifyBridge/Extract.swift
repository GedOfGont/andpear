import Foundation

/// Pulls a copyable verification code or link out of notification text.
enum Extract {
    private static let codeHints = [
        "kod", "code", "otp", "şifre", "sifre", "password", "pin", "doğrulama", "dogrulama",
        "verification", "verify", "onay", "tek kullanımlık", "giriş", "login", "g-", "passcode",
    ]

    static func code(in text: String) -> String? {
        let lower = text.lowercased()
        guard codeHints.contains(where: { lower.contains($0) }) else { return nil }
        // 4-8 digits, optionally written as "123 456" or "123-456"
        // a trailing sentence period is fine; "1250.75" or "10:30" style numbers are not codes
        let pattern = #"(?<![\d.,:/])(\d{3}[ -]\d{3}|\d{4,8})(?!\d|[.,:/]\d)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r]).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
    }

    static func link(in text: String) -> String? {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for m in det.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let u = m.url, u.scheme == "http" || u.scheme == "https" { return u.absoluteString }
        }
        return nil
    }
}

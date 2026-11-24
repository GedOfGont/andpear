import CryptoKit
import Foundation

/// Shared 256-bit secret. Generated once, stored in UserDefaults, shown to the user for pairing.
enum Pairing {
    private static let defaultsKey = "pairingKey"

    static var keyData: Data {
        if let s = UserDefaults.standard.string(forKey: defaultsKey), let d = Data(base64Encoded: s), d.count == 32 {
            return d
        }
        return regenerate()
    }

    @discardableResult
    static func regenerate() -> Data {
        let d = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        UserDefaults.standard.set(d.base64EncodedString(), forKey: defaultsKey)
        return d
    }

    /// Only set by the --render dev mode so screenshots never show the real key.
    static var previewKey: String?

    static var keyString: String { keyData.base64EncodedString() }

    static func encrypt(_ data: Data) -> Data? {
        try? AES.GCM.seal(data, using: SymmetricKey(data: keyData)).combined
    }

    /// Wire format: nonce(12) + ciphertext + tag(16)
    static func decrypt(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: SymmetricKey(data: keyData))
    }
}

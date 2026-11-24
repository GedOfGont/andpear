import AppKit
import CoreImage.CIFilterBuiltins

/// Pairing QR: notifybridge://pair?key=<base64, url-encoded>
enum QR {
    static func pairingImage() -> NSImage? {
        let key = Pairing.previewKey ?? Pairing.keyString
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("notifybridge://pair?key=\(encoded)".utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

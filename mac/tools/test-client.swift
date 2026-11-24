import Foundation
import CryptoKit
import Network
let key = Data(base64Encoded: CommandLine.arguments[1])!
let icon = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])).base64EncodedString()
let obj: [String: Any] = ["type": "post", "id": "icon-test-\(Int(Date().timeIntervalSince1970))", "pkg": "com.test", "app": "IkonTest", "title": "Küçük ikon testi", "text": "Sağda ikon görünmeli", "icon": icon]
let json = try JSONSerialization.data(withJSONObject: obj)
let sealed = try AES.GCM.seal(json, using: SymmetricKey(data: key)).combined!
var frame = Data(); var n = UInt32(sealed.count).bigEndian
withUnsafeBytes(of: &n) { frame.append(contentsOf: $0) }; frame.append(sealed)
let br = NWBrowser(for: .bonjour(type: "_notifybridge._tcp", domain: nil), using: .tcp)
br.browseResultsChangedHandler = { res, _ in
  guard let r = res.first else { return }
  br.cancel()
  let c = NWConnection(to: r.endpoint, using: .tcp)
  c.stateUpdateHandler = { s in if case .ready = s { c.send(content: frame, completion: .contentProcessed { _ in print("gönderildi"); exit(0) }) } }
  c.start(queue: .main)
}
br.start(queue: .main)
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { print("Bonjour bulunamadı"); exit(1) }
RunLoop.main.run()

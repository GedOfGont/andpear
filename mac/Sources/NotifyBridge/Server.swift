import Foundation
import Network

struct IncomingMessage: Decodable {
    let type: String?      // "post" (default) or "remove"
    let id: String?
    let pkg: String?
    let app: String?
    let title: String?
    let text: String?
    let icon: String?      // base64 PNG
    let reply: Bool?       // true when the phone notification has an inline-reply action
    let name: String?      // device name, sent in "hello"
    let battery: Int?      // phone battery percent, sent in "hello" and "ping"
    let charging: Bool?
    let ts: Double?        // when the notification was posted on the phone (ms since 1970)
    let missed: Bool?      // true when it was queued while the Mac was away
}

/// TCP listener advertised over Bonjour. Frames: 4-byte big-endian length + AES-GCM payload.
final class Server {
    private let queue = DispatchQueue(label: "notifybridge.server")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var lastSeen: [ObjectIdentifier: Date] = [:]
    var onMessage: ((IncomingMessage) -> Void)?
    var onStatus: ((String) -> Void)?
    var onReady: ((Int) -> Void)?

    func start() {
        do {
            let l = try NWListener(using: .tcp)
            l.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: "_notifybridge._tcp")
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] s in
                if case .ready = s, let p = l.port { self?.onStatus?("Dinleniyor (port \(p))"); self?.onReady?(Int(p.rawValue)) }
                if case .failed(let e) = s { self?.onStatus?("Hata: \(e)") }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            onStatus?("Başlatılamadı: \(error)")
        }
    }

    /// Sends an encrypted JSON frame back to every connected phone.
    func send(_ object: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: object),
              let sealed = Pairing.encrypt(json) else { return }
        var frame = Data()
        var n = UInt32(sealed.count).bigEndian
        withUnsafeBytes(of: &n) { frame.append(contentsOf: $0) }
        frame.append(sealed)
        queue.async { [weak self] in
            self?.connections.values.forEach { $0.send(content: frame, completion: .contentProcessed { _ in }) }
        }
    }

    /// When the phone last sent anything (nil if never since launch).
    func lastActivity() -> Date? { queue.sync { lastSeen.values.max() } }

    /// True while a phone has sent something (hello, ping or a message) in the last 150 seconds (it pings every 45).
    func isConnected() -> Bool {
        queue.sync { connections.keys.contains { (lastSeen[$0] ?? .distantPast).timeIntervalSinceNow > -150 } }
    }

    /// Drops connections that went silent, e.g. the phone left the Wi-Fi.
    func prune() {
        queue.async { [weak self] in
            guard let self else { return }
            for (id, c) in self.connections where (self.lastSeen[id] ?? .distantPast).timeIntervalSinceNow < -300 {
                c.cancel(); self.connections[id] = nil; self.lastSeen[id] = nil
            }
        }
    }

    private func accept(_ c: NWConnection) {
        let id = ObjectIdentifier(c)
        connections[id] = c
        lastSeen[id] = Date()
        c.stateUpdateHandler = { [weak self] s in
            switch s {
            case .failed, .cancelled:
                self?.connections[id] = nil
                self?.lastSeen[id] = nil
            default: break
            }
        }
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data); self.lastSeen[ObjectIdentifier(c)] = Date() }
            while buf.count >= 4 {
                let len = buf.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                if len <= 0 || len > 1_000_000 { c.cancel(); return }
                if buf.count < 4 + len { break }
                let frame = Data(buf.subdata(in: 4..<(4 + len)))
                buf.removeSubrange(0..<(4 + len))
                if let plain = Pairing.decrypt(frame),
                   let m = try? JSONDecoder().decode(IncomingMessage.self, from: plain) {
                    DispatchQueue.main.async { self.onMessage?(m) }
                }
                // frames that fail to authenticate are silently dropped
            }
            if done || err != nil { c.cancel(); return }
            self.receive(c, buffer: buf)
        }
    }
}

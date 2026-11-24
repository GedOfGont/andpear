import AppKit
import SwiftUI

/// Developer aid: `NotifyBridge --render <dir>` draws the real tabs with sample data to PNG files and exits.
/// Lets the UI be checked without screen-recording permission.
enum DevRender {
    @MainActor static func run(dir: String) {
        let model = AppModel.shared
        model.connected = true
        model.deviceName = "Pixel 9"
        model.battery = 51
        model.charging = true
        model.history = [
            HistoryEntry(nid: "1", app: "WhatsApp", title: "Ayşe", text: "Akşam görüşelim mi?", pkg: nil, date: Date().addingTimeInterval(-120), code: nil, link: nil),
            HistoryEntry(nid: "2", app: "Mesajlar", title: "Banka", text: "Doğrulama kodunuz: 482913. Kimseyle paylaşmayın.", pkg: nil, date: Date().addingTimeInterval(-900), code: "482913", link: nil),
            HistoryEntry(nid: "3", app: "Kargo", title: "Siparişin yolda", text: "Takip için https://kargo.example.com/t/889", pkg: nil, date: Date().addingTimeInterval(-7200), code: nil, link: "https://kargo.example.com/t/889"),
        ]
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func render<V: View>(_ name: String, _ view: V) {
            let r = ImageRenderer(content: view.frame(width: CGFloat(Double(ProcessInfo.processInfo.environment["NB_RENDER_WIDTH"] ?? "") ?? 660), height: 600)
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
            r.scale = 2
            guard let cg = r.cgImage else { print("\(name): render failed"); return }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            print("\(name): ok")
        }
        render("general", GeneralView(scrolls: false))
        model.notifStatus = .authorized
        model.listenPort = 63766
        render("diagnostics", DiagnosticsView(scrolls: false))
        for i in 0...3 { render("onboarding\(i)", OnboardingView(step: i)) }
        render("history", HistoryView())
        render("settings", SettingsView())
    }
}

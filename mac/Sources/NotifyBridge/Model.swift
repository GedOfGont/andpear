import AppKit
import Foundation
import SwiftUI
import UserNotifications

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var nid: String
    var app: String
    var title: String
    var text: String
    var pkg: String?
    var date: Date
    var code: String?
    var link: String?
}

private struct HistoryStore: Codable {
    var entries: [HistoryEntry]
    var icons: [String: String]
}

extension AppModel {
    /// SF Symbol matching the phone battery level.
    var batterySymbol: String {
        guard let b = battery else { return "battery.0percent" }
        if charging { return "battery.100percent.bolt" }
        switch b {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

/// Everything the UI shows. Mutated on the main thread only.
final class AppModel: ObservableObject {
    static let shared = AppModel()
    private static let soundKey = "notificationSound"   // unset = Funk, "" = system default, "none" = silent
    private static let maxHistory = 100

    @Published var connected = false
    @Published var deviceName = ""
    @Published var battery: Int? = nil
    @Published var charging = false
    @Published var finding = false
    @Published var onboarded: Bool = UserDefaults.standard.bool(forKey: "onboarded") {
        didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") }
    }
    @Published var notifStatus: UNAuthorizationStatus = .notDetermined
    @Published var listenPort: Int? = nil
    @Published var lastPhoneSeen: Date? = nil
    @Published var network = true
    @Published var wifi = true
    /// While set (and in the future) notifications are recorded but not shown.
    @Published var pausedUntil: Date? = {
        let t = UserDefaults.standard.double(forKey: "pausedUntil")
        return t > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: t) : nil
    }() {
        didSet { UserDefaults.standard.set(pausedUntil?.timeIntervalSince1970 ?? 0, forKey: "pausedUntil") }
    }
    var isPaused: Bool { (pausedUntil ?? .distantPast) > Date() }

    /// Notifications that arrived since the history was last looked at.
    @Published var unread = 0
    /// Tab shown in the main window ("Genel", "Geçmiş" or "Ayarlar").
    @Published var selectedTab = "Genel"
    @Published var shortcutEnabled: Bool = (UserDefaults.standard.object(forKey: "shortcut") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(shortcutEnabled, forKey: "shortcut")
            AppDelegate.shared?.applyShortcut()
        }
    }
    @Published var loginEnabled = false
    @Published var pairingKey = Pairing.keyString
    @Published var history: [HistoryEntry] = []
    @Published var icons: [String: String] = [:]   // package -> base64 PNG

    @Published var soundChoice: String = UserDefaults.standard.string(forKey: AppModel.soundKey) ?? "Funk" {
        didSet { UserDefaults.standard.set(soundChoice, forKey: AppModel.soundKey) }
    }
    @Published var clipSync: Bool = UserDefaults.standard.bool(forKey: "clipSync") {
        didSet { UserDefaults.standard.set(clipSync, forKey: "clipSync") }
    }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotifyBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let store = try? JSONDecoder().decode(HistoryStore.self, from: data) {
            history = store.entries
            icons = store.icons
        }
    }

    func addHistory(nid: String, app: String, title: String, text: String, pkg: String?, icon: String?, code: String?, link: String?, date: Date = Date()) {
        // a chat that keeps updating replaces its earlier entry
        history.removeAll { $0.nid == nid }
        history.insert(HistoryEntry(nid: nid, app: app, title: title, text: text, pkg: pkg, date: date, code: code, link: link), at: 0)
        history.sort { $0.date > $1.date }   // delivered-late (missed) entries keep their real time
        if history.count > Self.maxHistory { history.removeLast(history.count - Self.maxHistory) }
        if let pkg, let icon, !icon.isEmpty { icons[pkg] = icon }
        let used = Set(history.compactMap { $0.pkg })
        icons = icons.filter { used.contains($0.key) }
        save()
    }

    func clearHistory() {
        history = []
        icons = [:]
        save()
    }

    private func save() {
        let store = HistoryStore(entries: history, icons: icons)
        if let data = try? JSONEncoder().encode(store) { try? data.write(to: fileURL, options: .atomic) }
    }
}

import AppKit
import SwiftUI
import UserNotifications

/// "Why isn't it working?": every precondition with a plain-language verdict and, where possible, a fix button.
struct DiagnosticsView: View {
    @ObservedObject var model = AppModel.shared
    /// false only for the developer render, where ScrollView draws nothing.
    var scrolls = true

    enum Level { case ok, warn, bad }
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let level: Level
        var action: (title: String, run: () -> Void)? = nil
    }

    var items: [Item] {
        var list: [Item] = []

        switch model.notifStatus {
        case .authorized, .provisional, .ephemeral:
            list.append(Item(title: L("Bildirim izni"), detail: L("macOS bildirimleri gösterebilir"), level: .ok))
        case .denied:
            list.append(Item(title: L("Bildirim izni"), detail: L("macOS’ta NotifyBridge bildirimleri kapalı"),
                             level: .bad, action: (L("Sistem Ayarları’nı aç"), { AppDelegate.shared.openNotificationSettings() })))
        default:
            list.append(Item(title: L("Bildirim izni"), detail: L("İzin henüz verilmedi"),
                             level: .warn, action: (L("İzin ver"), { AppDelegate.shared.requestNotificationPermission() })))
        }

        if model.connected {
            let name = model.deviceName.isEmpty ? "" : "\(model.deviceName) · "
            list.append(Item(title: L("Telefon bağlantısı"), detail: String(format: L("%@bağlı"), name), level: .ok))
        } else {
            var detail = L("Telefon bağlı değil. Telefonda NotifyBridge’in açık ve aynı Wi-Fi ağında olduğundan emin ol.")
            if let seen = model.lastPhoneSeen {
                detail += " " + String(format: L("Son görülme: %@."), Self.ago(seen))
            }
            list.append(Item(title: L("Telefon bağlantısı"), detail: detail, level: .bad))
        }

        if !model.network {
            list.append(Item(title: L("Mac ağı"), detail: L("Mac’in internet/ağ bağlantısı yok"), level: .bad))
        } else if model.wifi {
            list.append(Item(title: L("Mac ağı"), detail: L("Wi-Fi bağlı"), level: .ok))
        } else {
            list.append(Item(title: L("Mac ağı"), detail: L("Kablolu ya da başka bir ağ. Telefonla aynı ağda olduğundan emin ol."), level: .warn))
        }

        if let port = model.listenPort {
            list.append(Item(title: L("Yerel dinleyici"), detail: String(format: L("Telefonu bekliyor (port %d)"), port), level: .ok))
        } else {
            list.append(Item(title: L("Yerel dinleyici"), detail: L("Başlamadı. Uygulamayı kapatıp yeniden aç; sorun sürerse Yerel Ağ iznini kontrol et."), level: .bad))
        }

        if model.isPaused {
            list.append(Item(title: L("Bildirimler"), detail: String(format: L("Duraklatıldı · %@’e kadar"), AppDelegate.clock(model.pausedUntil)),
                             level: .warn, action: (L("Duraklatmayı bitir"), { AppDelegate.shared.resume() })))
        } else {
            list.append(Item(title: L("Bildirimler"), detail: L("Gösteriliyor"), level: .ok))
        }

        list.append(Item(title: L("Pano senkronu"), detail: model.clipSync ? L("Mac panosu telefona gönderiliyor") : L("Kapalı"), level: .ok))

        if Bundle.main.bundlePath.hasPrefix("/Applications") {
            list.append(Item(title: L("Uygulama konumu"), detail: L("Applications klasöründe"), level: .ok))
        } else {
            list.append(Item(title: L("Uygulama konumu"), detail: L("Applications klasöründe değil. Açılışta başlatma için oraya taşı."), level: .warn))
        }
        return list
    }

    private var summary: (String, Level) {
        let bad = items.filter { $0.level == .bad }.count
        let warn = items.filter { $0.level == .warn }.count
        if bad > 0 { return (String(format: L("%d sorun var"), bad), .bad) }
        if warn > 0 { return (String(format: L("%d uyarı var"), warn), .warn) }
        return (L("Her şey yolunda"), .ok)
    }

    var body: some View {
        Group { if scrolls { ScrollView { content } } else { content } }
    }

    private var content: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: icon(summary.1)).font(.system(size: 30)).foregroundColor(color(summary.1))
                Text(summary.0).font(.title2.weight(.bold))
                Spacer()
                Button { copyReport() } label: { Label(L("Raporu kopyala"), systemImage: "doc.on.doc") }
                    .buttonStyle(PillButtonStyle(compact: true))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(color(summary.1).opacity(0.12)))

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < items.count - 1 { Divider().padding(.leading, 56) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
        }
        .padding(24)
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon(item.level)).font(.system(size: 20)).foregroundColor(color(item.level)).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                Text(item.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let action = item.action {
                Button { action.run() } label: { Text(action.title) }
                    .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func icon(_ l: Level) -> String {
        switch l { case .ok: return "checkmark.circle.fill"; case .warn: return "exclamationmark.triangle.fill"; case .bad: return "xmark.octagon.fill" }
    }

    private func color(_ l: Level) -> Color {
        switch l { case .ok: return nbGreen; case .warn: return .orange; case .bad: return .red }
    }

    static func ago(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func copyReport() {
        var lines = ["NotifyBridge diagnostics", "version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")",
                     "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        for i in items {
            let tag = i.level == .ok ? "OK  " : (i.level == .warn ? "WARN" : "FAIL")
            lines.append("[\(tag)] \(i.title): \(i.detail)")
        }
        AppDelegate.shared.copyText(lines.joined(separator: "\n"))
    }
}

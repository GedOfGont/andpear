import AppKit
import SwiftUI

private let brandTeal = nbTeal
private let brandGreen = nbGreen

// MARK: - shell

struct MainView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "Genel", history = "Geçmiş", diagnostics = "Tanı", settings = "Ayarlar"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "antenna.radiowaves.left.and.right"
            case .history: return "clock.arrow.circlepath"
            case .diagnostics: return "stethoscope"
            case .settings: return "gearshape"
            }
        }
    }

    @ObservedObject private var model = AppModel.shared

    /// The selected tab lives in the model so the menu and the global shortcut can open a specific one.
    private var tab: Binding<Tab?> {
        Binding(
            get: { Tab(rawValue: model.selectedTab) ?? .general },
            set: { new in
                model.selectedTab = new?.rawValue ?? Tab.general.rawValue
                if new == .history { model.unread = 0 }
            })
    }

    var body: some View {
        Group { if model.onboarded { splitView } else { OnboardingView() } }
            .frame(minWidth: 780, minHeight: 540)
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: tab) {
                ForEach(Tab.allCases) { t in
                    // .tag must be the last modifier or the row is no longer selectable
                    Label(L(t.rawValue), systemImage: t.icon)
                        .badge(t == .history ? model.unread : 0)
                        .tag(t)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            switch tab.wrappedValue ?? .general {
            case .general: GeneralView()
            case .history: HistoryView()
            case .diagnostics: DiagnosticsView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 780, minHeight: 540)
    }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
    }
}

// MARK: - general

struct GeneralView: View {
    @ObservedObject var model = AppModel.shared
    @State private var confirmReset = false
    /// false only for the developer render, where ScrollView draws nothing.
    var scrolls = true

    var body: some View {
        Group {
            if scrolls { ScrollView { content } } else { content }
        }
        .confirmationDialog(L("Eşleşme sıfırlansın mı?"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("Sıfırla"), role: .destructive) { AppDelegate.shared.resetKey() }
            Button(L("Vazgeç"), role: .cancel) {}
        } message: {
            Text(L("Yeni bir anahtar üretilir. Telefonu yeni QR ile yeniden eşleştirmen gerekir."))
        }
    }

    private var content: some View {
            VStack(spacing: 18) {
                hero
                Card(title: L("Telefonu eşleştir")) {
                    HStack(alignment: .top, spacing: 22) {
                        Group {
                            if let img = QR.pairingImage(), !model.pairingKey.isEmpty {
                                Image(nsImage: img).interpolation(.none).resizable().scaledToFit()
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 168, height: 168)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))

                        VStack(alignment: .leading, spacing: 10) {
                            step(1, L("Telefonda NotifyBridge’i aç"))
                            step(2, L("Kurulum bölümünde “QR oku”ya bas"))
                            step(3, L("Bu kodu telefona okut"))
                            Spacer(minLength: 6)
                            // side by side when they fit, stacked when the window is narrow
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) { copyKeyButton; resetButton }
                                VStack(alignment: .leading, spacing: 8) { copyKeyButton; resetButton }
                            }
                        }
                    }
                }
                Card(title: L("Bildirimleri duraklat")) {
                    if model.isPaused {
                        Text(String(format: L("Duraklatıldı · %@’e kadar. Bu sürede gelenler Geçmiş’e kaydedilir ama gösterilmez."), AppDelegate.clock(model.pausedUntil)))
                            .font(.callout).foregroundStyle(.secondary)
                        Button { AppDelegate.shared.resume() } label: {
                            Label(L("Duraklatmayı bitir"), systemImage: "play.fill")
                        }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { pauseButtons }
                            VStack(alignment: .leading, spacing: 8) { pauseButtons }
                        }
                    }
                }
                Card(title: L("Telefon")) {
                    HStack(spacing: 10) {
                        Button {
                            AppDelegate.shared.toggleFind()
                        } label: {
                            Label(model.finding ? L("Çalmayı durdur") : L("Telefonumu bul"),
                                  systemImage: model.finding ? "stop.circle.fill" : "iphone.radiowaves.left.and.right")
                        }
                        .buttonStyle(PillButtonStyle(kind: model.finding ? .danger : .primary))
                        .disabled(!model.connected && !model.finding)

                        Button { AppDelegate.shared.sendTest() } label: {
                            Label(L("Test bildirimi"), systemImage: "bell")
                        }
                        .buttonStyle(PillButtonStyle())
                        Spacer()
                    }
                    if !model.connected {
                        Text(L("Telefon bağlı değilken “Telefonumu bul” kullanılamaz."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
    }

    @ViewBuilder private var pauseButtons: some View {
        Button { AppDelegate.shared.pause(minutes: 30) } label: { Label(L("30 dakika"), systemImage: "moon") }
            .buttonStyle(PillButtonStyle())
        Button { AppDelegate.shared.pause(minutes: 60) } label: { Label(L("1 saat"), systemImage: "moon") }
            .buttonStyle(PillButtonStyle())
        Button { AppDelegate.shared.pauseUntilTomorrow() } label: { Label(L("Yarına kadar"), systemImage: "moon.zzz") }
            .buttonStyle(PillButtonStyle())
    }

    private var copyKeyButton: some View {
        Button { AppDelegate.shared.copyKey() } label: {
            Label(L("Anahtarı kopyala"), systemImage: "doc.on.doc")
        }
        .buttonStyle(PillButtonStyle())
    }

    private var resetButton: some View {
        Button { confirmReset = true } label: {
            Label(L("Eşleşmeyi sıfırla…"), systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(PillButtonStyle(kind: .danger))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.white.opacity(model.connected ? 1 : 0.5)).frame(width: 10, height: 10)
                Text("NotifyBridge").font(.subheadline.weight(.medium)).opacity(0.9)
            }
            Text(model.connected ? L("Telefon bağlı") : L("Telefon bekleniyor"))
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(model.connected
                 ? (model.deviceName.isEmpty ? L("Bildirimler Mac’ine iletiliyor") : String(format: L("%@ · bildirimler iletiliyor"), model.deviceName))
                 : L("Telefonda uygulamayı aç ve aynı Wi-Fi ağında olduğundan emin ol"))
                .font(.callout).opacity(0.95)
            if model.connected, let b = model.battery {
                HStack(spacing: 6) {
                    Image(systemName: model.batterySymbol)
                    Text(String(format: L("%%%d"), b) + (model.charging ? L(" · şarj oluyor") : ""))
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.22)))
                .padding(.top, 4)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(
                colors: model.connected ? [brandTeal, brandGreen] : [Color(white: 0.45), Color(white: 0.58)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.3), value: model.connected)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.caption.weight(.bold)).foregroundColor(.white)
                .frame(width: 22, height: 22).background(Circle().fill(brandTeal))
            Text(text)
        }
    }
}

// MARK: - history

private enum IconCache {
    static var images: [String: NSImage] = [:]
    static func image(_ b64: String) -> NSImage? {
        if let i = images[b64] { return i }
        guard let d = Data(base64Encoded: b64), let i = NSImage(data: d) else { return nil }
        images[b64] = i
        return i
    }
}

private func relative(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "tr_TR")
    f.unitsStyle = .short
    return f.localizedString(for: date, relativeTo: Date())
}

struct HistoryView: View {
    @ObservedObject var model = AppModel.shared
    @State private var query = ""

    private var filtered: [HistoryEntry] {
        guard !query.isEmpty else { return model.history }
        return model.history.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query)
                || $0.app.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if model.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.system(size: 42)).foregroundStyle(.tertiary)
                    Text(L("Henüz bildirim yok")).font(.headline)
                    Text(L("Telefondan gelen bildirimler burada listelenir.")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                Text(L("Eşleşen bildirim yok")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { HistoryRow(entry: $0) }
                    .listStyle(.inset)
            }
        }
        .searchable(text: $query, prompt: L("Bildirimlerde ara"))
        .toolbar {
            ToolbarItem {
                Button { model.clearHistory() } label: { Label(L("Geçmişi temizle"), systemImage: "trash") }
                    .disabled(model.history.isEmpty)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @ObservedObject var model = AppModel.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.title.isEmpty ? entry.app : entry.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text(relative(entry.date)).font(.caption).foregroundStyle(.secondary)
                }
                if !entry.title.isEmpty {
                    Text(entry.app).font(.caption).foregroundStyle(.secondary)
                }
                Text(entry.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if entry.code != nil || entry.link != nil {
                    HStack {
                        if let code = entry.code {
                            Button(String(format: L("Kodu kopyala: %@"), code)) { AppDelegate.shared.copyText(code) }
                        }
                        if let link = entry.link {
                            Button(L("Bağlantıyı kopyala")) { AppDelegate.shared.copyText(link) }
                        }
                    }
                    .buttonStyle(PillButtonStyle(compact: true)).padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var icon: some View {
        if let pkg = entry.pkg, let b64 = model.icons[pkg], let img = IconCache.image(b64) {
            Image(nsImage: img).resizable().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 9))
        } else if entry.app == "NotifyBridge" {
            // test notifications come from the app itself
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
        } else {
            RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.08)).frame(width: 38, height: 38)
                .overlay(Image(systemName: "app.dashed").foregroundStyle(.secondary))
        }
    }
}

// MARK: - settings

struct SettingsView: View {
    @ObservedObject var model = AppModel.shared
    private let sounds: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return names.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
    }()

    var body: some View {
        Form {
            Section(L("Bildirim sesi")) {
                Picker(L("Ses"), selection: $model.soundChoice) {
                    Text("Sistem sesi").tag("")
                    Text("Sessiz").tag("none")
                    Divider()
                    ForEach(sounds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: model.soundChoice) { _ in AppDelegate.shared.previewSound() }
            }
            Section {
                Toggle(L("Mac panosunu telefona otomatik gönder"), isOn: $model.clipSync)
            } header: {
                Text(L("Pano"))
            } footer: {
                Text(L("Şifre yöneticilerinin kopyaladığı gizli içerikler gönderilmez. Telefonda “Mac’ten gelen panoyu al” da açık olmalı. Telefondan Mac’e göndermek için telefondaki Paylaş menüsünü ya da uygulamadaki düğmeyi kullan."))
            }
            Section {
                Toggle(L("Geçmişi her yerden aç (⌃⌥N)"), isOn: $model.shortcutEnabled)
            } header: {
                Text(L("Kısayol"))
            } footer: {
                Text(L("Control + Option + N tuşlarına birlikte basınca NotifyBridge geçmişi açılır. Başka bir uygulamayla çakışırsa kapatabilirsin."))
            }
            Section(L("Kurulum")) {
                Button(L("Kurulum sihirbazını yeniden aç")) { model.onboarded = false }
            }
            Section(L("Genel")) {
                Toggle(L("Oturum açılınca başlat"), isOn: Binding(
                    get: { model.loginEnabled },
                    set: { _ in AppDelegate.shared.toggleLogin() }))
            }
        }
        .formStyle(.grouped)
    }
}

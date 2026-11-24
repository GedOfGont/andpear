import AppKit
import Carbon.HIToolbox
import Combine
import Network
import ServiceManagement
import UserNotifications

/// Dev aid: appends to /tmp/notifybridge-debug.log only while /tmp/notifybridge-debug.enabled exists.
func debugLog(_ message: String) {
    guard FileManager.default.fileExists(atPath: "/tmp/notifybridge-debug.enabled") else { return }
    let line = "\(Date()) \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/notifybridge-debug.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var shared: AppDelegate!

    private let model = AppModel.shared
    private var statusItem: NSStatusItem!
    private let server = Server()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let center = UNUserNotificationCenter.current()
    private var lastPasteCount = NSPasteboard.general.changeCount
    private var statusTimer: Timer?
    private var clipTimer: Timer?
    private let historyItem = NSMenuItem()
    private var bag = Set<AnyCancellable>()
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private let pauseItem = NSMenuItem()
    private var resumeTimer: Timer?
    private var pausedCount = 0
    private var missed: [IncomingMessage] = []
    private var missedTimer: Timer?
    private let pathMonitor = NWPathMonitor()

    // MARK: launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        installMainMenu()
        setupStatusItem()
        setupNotifications()

        server.onMessage = { [weak self] m in self?.handle(m) }
        server.onReady = { [weak self] port in DispatchQueue.main.async { self?.model.listenPort = port } }
        server.start()

        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.model.network = path.status == .satisfied
                self?.model.wifi = path.usesInterfaceType(.wifi)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "notifybridge.path"))
        refreshNotificationStatus()
        // the user may flip the permission in System Settings and come back
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshNotificationStatus()
        }
        if !model.onboarded { MainWindow.shared.show() }

        refreshLogin()
        refreshStatus()
        model.$unread.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateUnreadUI() }.store(in: &bag)
        applyShortcut()
        if model.isPaused { scheduleResume() }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.server.prune()
            if let u = self?.model.pausedUntil, u <= Date() { self?.resume() }
            self?.refreshStatus()
        }
        clipTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.pollPasteboard() }
    }

    /// Clicking the app in Finder/Launchpad while it runs in the menu bar opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.shared.show()
        return true
    }

    /// Without a main menu ⌘C/⌘V/⌘W/⌘Q do nothing inside the window.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: L("AndPear’i Gizle"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("AndPear’den Çık"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: L("Düzen")); editItem.submenu = edit
        edit.addItem(withTitle: L("Kes"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Kopyala"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Yapıştır"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Tümünü Seç"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: L("Pencere")); winItem.submenu = win
        win.addItem(withTitle: L("Kapat"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: L("Küçült"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.mainMenu = main
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let icon = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "AndPear")?.withSymbolConfiguration(cfg)
        icon?.isTemplate = true   // follows light/dark menu bar automatically
        statusItem.button?.image = icon

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(menuItem(L("AndPear’i aç…"), #selector(openWindow), "o"))
        historyItem.title = L("Geçmişi aç")
        historyItem.action = #selector(openHistory)
        historyItem.target = self
        menu.addItem(historyItem)
        pauseItem.title = L("Duraklat")
        let pauseMenu = NSMenu()
        for (title, tag) in [(L("30 dakika"), 30), (L("1 saat"), 60), (L("2 saat"), 120), (L("Yarına kadar"), -1)] {
            let i = NSMenuItem(title: title, action: #selector(pauseFromMenu(_:)), keyEquivalent: "")
            i.target = self; i.tag = tag
            pauseMenu.addItem(i)
        }
        pauseMenu.addItem(.separator())
        let end = NSMenuItem(title: L("Duraklatmayı bitir"), action: #selector(pauseFromMenu(_:)), keyEquivalent: "")
        end.target = self; end.tag = -2
        pauseMenu.addItem(end)
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)
        menu.addItem(menuItem(L("Telefonumu bul"), #selector(toggleFind), ""))
        menu.addItem(menuItem(L("Test bildirimi gönder"), #selector(sendTest), "t"))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("Çıkış"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func setupNotifications() {
        // One category per combination of available actions: reply / copy code / copy link.
        let replyAction = UNTextInputNotificationAction(
            identifier: "reply", title: L("Yanıtla"), options: [],
            textInputButtonTitle: L("Gönder"), textInputPlaceholder: L("Yanıt yaz…"))
        let codeAction = UNNotificationAction(identifier: "copyCode", title: L("Kodu kopyala"), options: [])
        let linkAction = UNNotificationAction(identifier: "copyLink", title: L("Bağlantıyı kopyala"), options: [])
        var categories = Set<UNNotificationCategory>()
        for r in [false, true] { for c in [false, true] { for l in [false, true] {
            var actions: [UNNotificationAction] = []
            if r { actions.append(replyAction) }
            if c { actions.append(codeAction) }
            if l { actions.append(linkAction) }
            categories.insert(UNNotificationCategory(
                identifier: AppDelegate.categoryID(reply: r, code: c, link: l),
                actions: actions, intentIdentifiers: [], options: [.customDismissAction]))
        } } }
        center.setNotificationCategories(categories)
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func categoryID(reply: Bool, code: Bool, link: Bool) -> String {
        "nb" + (reply ? "R" : "") + (code ? "C" : "") + (link ? "L" : "")
    }

    // MARK: unread counter and global shortcut

    private func updateUnreadUI() {
        let n = model.unread
        debugLog("unread=\(n)")
        statusItem.button?.title = n > 0 ? " " + (n > 99 ? "99+" : String(n)) : ""
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        statusItem.button?.imagePosition = n > 0 ? .imageLeading : .imageOnly
        historyItem.title = n > 0 ? String(format: L("Geçmişi aç (%d yeni)"), n) : L("Geçmişi aç")
    }

    @objc func openHistory() {
        model.selectedTab = "Geçmiş"
        model.unread = 0
        MainWindow.shared.show()
    }

    /// Registers (or removes) the system-wide ⌃⌥N hot key. Carbon hot keys need no extra permission.
    func applyShortcut() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        guard model.shortcutEnabled else { return }
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { AppDelegate.shared.openHistory() }
                return noErr
            }, 1, &spec, nil, &hotKeyHandler)
        }
        let id = EventHotKeyID(signature: OSType(0x4E425247), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        debugLog("hotkey register status=\(status) (0 = ok)")
    }

    // MARK: status

    private func refreshStatus() {
        let c = server.isConnected()
        model.lastPhoneSeen = server.lastActivity()
        if c != model.connected { model.connected = c }
        statusItem.button?.appearsDisabled = !c

        updateIcon()
        pauseItem.title = model.isPaused ? String(format: L("Duraklatıldı · %@’e kadar"), Self.clock(model.pausedUntil)) : L("Duraklat")
        let line = NSMutableAttributedString(
            string: "● ", attributes: [.foregroundColor: c ? NSColor.systemGreen : NSColor.systemGray])
        let name = model.deviceName.isEmpty ? "" : " · \(model.deviceName)"
        let battery = model.battery.map { " · " + String(format: L("%%%d"), $0) + (model.charging ? " ⚡︎" : "") } ?? ""
        line.append(NSAttributedString(string: c ? L("Telefon bağlı") + name + battery : L("Telefon bekleniyor…")))
        statusLine.attributedTitle = line
    }

    // MARK: notification permission

    func refreshNotificationStatus() {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async { self?.model.notifStatus = settings.authorizationStatus }
        }
    }

    func requestNotificationPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in self?.refreshNotificationStatus() }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(url) }
    }

    // MARK: pause

    static func clock(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: d)
    }

    private func updateIcon() {
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let name = model.isPaused ? "bell.slash.fill" : "bell.badge.fill"
        let icon = NSImage(systemSymbolName: name, accessibilityDescription: "AndPear")?.withSymbolConfiguration(cfg)
        icon?.isTemplate = true
        statusItem.button?.image = icon
    }

    @objc private func pauseFromMenu(_ sender: NSMenuItem) {
        switch sender.tag {
        case -2: resume()
        case -1: pauseUntilTomorrow()
        default: pause(minutes: sender.tag)
        }
    }

    func pause(minutes: Int) { pause(until: Date().addingTimeInterval(Double(minutes) * 60)) }

    func pauseUntilTomorrow() {
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 8, minute: 0), matchingPolicy: .nextTime)
        pause(until: next ?? Date().addingTimeInterval(8 * 3600))
    }

    func pause(until date: Date) {
        model.pausedUntil = date
        pausedCount = 0
        scheduleResume()
        refreshStatus()
    }

    func resume() {
        let n = pausedCount
        model.pausedUntil = nil
        resumeTimer?.invalidate()
        pausedCount = 0
        refreshStatus()
        if n > 0 {
            postSummary(title: L("Duraklatma bitti"), body: String(format: L("%d bildirim geldi. Geçmiş’ten bakabilirsin."), n))
        }
    }

    private func scheduleResume() {
        resumeTimer?.invalidate()
        guard let d = model.pausedUntil else { return }
        resumeTimer = Timer(fire: d, interval: 0, repeats: false) { [weak self] _ in self?.resume() }
        RunLoop.main.add(resumeTimer!, forMode: .common)
    }

    /// One banner instead of a flood: used after a pause and for notifications missed while the Mac was away.
    private func postSummary(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = notificationSound()
        content.userInfo = ["open": "history"]
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func scheduleMissedSummary() {
        missedTimer?.invalidate()
        missedTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            guard let self, !self.missed.isEmpty else { return }
            let items = self.missed
            self.missed = []
            let lines = items.prefix(3).map { m -> String in
                let t = (m.title ?? "").isEmpty ? (m.text ?? "") : (m.title ?? "")
                return "\(m.app ?? ""): \(t)"
            }
            var body = lines.joined(separator: "\n")
            if items.count > 3 { body += "\n… +\(items.count - 3)" }
            self.postSummary(title: String(format: L("Mac kapalıyken %d bildirim geldi"), items.count), body: body)
        }
    }

    // MARK: actions used by the UI and the menu

    @objc func openWindow() { MainWindow.shared.show() }

    @objc func sendTest() {
        show(id: UUID().uuidString, title: "AndPear", app: L("Test"), body: L("Test bildirimi çalışıyor"), pkg: nil, iconB64: nil)
    }

    @objc func toggleFind() {
        if model.finding {
            server.send(["type": "findStop"])
            model.finding = false
        } else {
            guard model.connected else { return }
            server.send(["type": "find"])
            model.finding = true
            // the phone stops by itself after a minute
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.model.finding = false }
        }
    }

    func copyKey() { copyText(Pairing.keyString) }

    func copyText(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        lastPasteCount = NSPasteboard.general.changeCount
    }

    func resetKey() {
        Pairing.regenerate()
        model.pairingKey = Pairing.keyString
    }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let a = NSAlert()
            a.messageText = L("Açılışta başlatma ayarlanamadı")
            a.informativeText = error.localizedDescription + "\n\n" + L("Uygulama /Applications klasöründe olmalı.")
            a.runModal()
        }
        refreshLogin()
    }

    private func refreshLogin() { model.loginEnabled = SMAppService.mainApp.status == .enabled }

    // MARK: sound

    func previewSound() {
        let v = model.soundChoice
        guard !v.isEmpty, v != "none" else { return }
        installSound(v)
        NSSound(named: NSSound.Name(v))?.play()
    }

    /// Notification sounds are looked up in ~/Library/Sounds, so copy the chosen system sound there.
    private func installSound(_ name: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds")
        let dest = dir.appendingPathComponent("\(name).aiff")
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(atPath: "/System/Library/Sounds/\(name).aiff", toPath: dest.path)
    }

    private func notificationSound() -> UNNotificationSound? {
        switch model.soundChoice {
        case "": return .default
        case "none": return nil
        case let name:
            installSound(name)
            return UNNotificationSound(named: UNNotificationSoundName("\(name).aiff"))
        }
    }

    // MARK: clipboard (Mac -> phone)

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteCount else { return }
        lastPasteCount = pb.changeCount
        guard model.clipSync, model.connected else { return }
        let types = pb.types?.map { $0.rawValue } ?? []
        // password managers mark secrets so clipboard tools skip them
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { return }
        guard let s = pb.string(forType: .string), !s.isEmpty, s.count <= 50_000 else { return }
        server.send(["type": "clip", "text": s])
    }

    // MARK: phone -> Mac

    private func handle(_ m: IncomingMessage) {
        switch m.type ?? "post" {
        case "hello":
            model.deviceName = m.name ?? ""
            updateBattery(m)
            refreshStatus()
        case "ping":
            updateBattery(m)
            refreshStatus()
        case "remove":
            if let id = m.id { center.removeDeliveredNotifications(withIdentifiers: [id]) }
        case "clip":
            guard let text = m.text, !text.isEmpty else { return }
            copyText(text)
            let preview = text.count > 80 ? String(text.prefix(80)) + "…" : text
            if !model.isPaused { show(id: UUID().uuidString, title: L("Pano telefondan alındı"), app: "AndPear", body: preview, pkg: nil, iconB64: nil) }
        default:
            let id = m.id ?? UUID().uuidString
            let title = m.title ?? "", app = m.app ?? "", body = m.text ?? ""
            let both = title + " " + body
            let when = m.ts.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            model.addHistory(nid: id, app: app, title: title, text: body, pkg: m.pkg, icon: m.icon,
                             code: Extract.code(in: both), link: Extract.link(in: both), date: when)
            if !MainWindow.shared.isShowingHistory { model.unread += 1 }
            debugLog("post id=\(id) missed=\(m.missed == true) paused=\(model.isPaused) title=\(title)")
            if m.missed == true {          // queued on the phone while the Mac was away: summarise instead of N banners
                missed.append(m)
                scheduleMissedSummary()
                return
            }
            if model.isPaused { pausedCount += 1; return }
            show(id: id, title: title, app: app, body: body, pkg: m.pkg, iconB64: m.icon, canReply: m.reply == true)
        }
    }

    private func updateBattery(_ m: IncomingMessage) {
        if let b = m.battery { model.battery = b }
        if let c = m.charging { model.charging = c }
    }

    private func show(id: String, title: String, app: String, body: String, pkg: String?, iconB64: String?, canReply: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? app : title
        if !title.isEmpty { content.subtitle = app }
        content.body = body
        content.sound = notificationSound()
        let code = Extract.code(in: title + " " + body)
        let link = Extract.link(in: title + " " + body)
        content.categoryIdentifier = AppDelegate.categoryID(reply: canReply, code: code != nil, link: link != nil)
        var info: [String: String] = ["id": id]
        if let code { info["code"] = code }
        if let link { info["link"] = link }
        content.userInfo = info
        if let b64 = iconB64, let data = Data(base64Encoded: b64) {
            // the system moves attachment files, so write a fresh copy each time
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("nbicon-\(UUID().uuidString).png")
            if (try? data.write(to: url)) != nil,
               let att = try? UNNotificationAttachment(identifier: "icon", url: url) {
                content.attachments = [att]
            }
        }
        // same identifier replaces the earlier banner, e.g. a chat that keeps updating
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: notification delegate (Mac -> phone)

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    /// Dismissing or clicking a banner on the Mac clears it on the phone too.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if (info["open"] as? String) == "history" {
            DispatchQueue.main.async { self.openHistory() }
            done()
            return
        }
        if response.actionIdentifier == "copyCode" || response.actionIdentifier == "copyLink" {
            let value = info[response.actionIdentifier == "copyCode" ? "code" : "link"] as? String
            if let value { copyText(value) }
            done()
            return
        }
        if let id = info["id"] as? String {
            if let text = (response as? UNTextInputNotificationResponse)?.userText, !text.isEmpty {
                server.send(["type": "reply", "id": id, "text": text])
            } else {
                server.send(["type": "dismiss", "id": id])
            }
        }
        done()
    }
}

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--render"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { DevRender.run(dir: CommandLine.arguments[i + 1]) }
    exit(0)
}
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

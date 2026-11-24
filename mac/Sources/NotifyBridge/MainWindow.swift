import AppKit
import SwiftUI

/// The app is a menu bar accessory; while this window is open it behaves like a normal app (Dock icon, ⌘ shortcuts).
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "NotifyBridge"
            w.contentViewController = NSHostingController(rootView: MainView())
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setFrameAutosaveName("NotifyBridgeMain")
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// True while the window is frontmost and showing the history, i.e. new notifications are seen at once.
    var isShowingHistory: Bool { (window?.isKeyWindow ?? false) && AppModel.shared.selectedTab == "Geçmiş" }

    func windowDidBecomeKey(_ notification: Notification) {
        if AppModel.shared.selectedTab == "Geçmiş" { AppModel.shared.unread = 0 }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

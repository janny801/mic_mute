import AppKit
import SwiftUI

public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?

    public func showWindow() {
        NSApp.setActivationPolicy(.regular)

        if let existing = window {
            existing.orderFrontRegardless()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "MicMute — Settings & Controls"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.center()

        self.window = newWindow

        newWindow.orderFrontRegardless()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

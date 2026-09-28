import AppKit
import SwiftUI

public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var appResignObserver: Any?

    private override init() {
        super.init()
        // Stop any active mic testing when MicMute loses focus to another app
        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MicTestManager.shared.stopAll()
        }
    }

    deinit {
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @objc public func showWindow() {
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
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 720),
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

    @objc public func closeWindow() {
        MicTestManager.shared.stopAll()
        window?.orderOut(nil)
        // Keep MicMute active so pressing ⌘, right after Done re-opens cleanly
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        MicTestManager.shared.stopAll()
        window = nil
    }

    public func windowWillMiniaturize(_ notification: Notification) {
        MicTestManager.shared.stopAll()
    }
}

import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run with regular activation policy so window appears in front and shows in Dock
        NSApp.setActivationPolicy(.regular)

        // Initialize core engines
        _ = AudioEngine.shared
        _ = SoundCueManager.shared
        _ = SettingsStore.shared
        _ = PermissionManager.shared
        _ = HotkeyManager.shared

        // Setup menu bar item
        MenuBarController.shared.setup()

        // Open UI window immediately on launch so user can see it running
        DispatchQueue.main.async {
            SettingsWindowController.shared.showWindow()
        }

        NSLog("[MacMicMute] Application launched successfully with UI window and menu bar item.")
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar even when Preferences window is closed
        return false
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When user clicks dock icon or reopens app, show the UI window
        if !flag {
            SettingsWindowController.shared.showWindow()
        }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterHotkeys()
    }
}

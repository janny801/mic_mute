import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run with regular activation policy so window appears in front and shows in Dock
        NSApp.setActivationPolicy(.regular)

        // Setup Main Menu for standard macOS keyboard shortcuts (⌘,, ⌘Q, ⌘W)
        setupMainMenu()

        // Setup local key monitor for ⌘,
        setupKeyMonitors()

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

        NSLog("[MicMute] Application launched successfully with UI window and menu bar item.")
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "MicMute")
        let prefsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = self
        appMenu.addItem(prefsItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide MicMute", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit MicMute", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        // Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(closeCurrentWindow), keyEquivalent: "w")
        closeItem.target = self
        windowMenu.addItem(closeItem)
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func setupKeyMonitors() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Intercept ⌘, anywhere within MicMute
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
                SettingsWindowController.shared.showWindow()
                return nil
            }
            return event
        }
    }

    @objc public func openPreferences() {
        SettingsWindowController.shared.showWindow()
    }

    @objc public func closeCurrentWindow() {
        SettingsWindowController.shared.closeWindow()
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

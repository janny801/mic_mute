import Foundation
import AppKit
import ApplicationServices

/// Synchronizes mute/unmute state with active Apple FaceTime calls.
public final class FaceTimeSyncManager {
    public static let shared = FaceTimeSyncManager()

    private init() {}

    /// Synchronizes FaceTime call mute state with the requested state.
    public func syncFaceTimeMute(shouldBeMuted: Bool) {
        guard SettingsStore.shared.faceTimeSyncEnabled else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performSync(shouldBeMuted: shouldBeMuted)
        }
    }

    private func performSync(shouldBeMuted: Bool) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.FaceTime")
        guard let ft = apps.first else { return }

        let pid = ft.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var menuBarObj: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarObj) == .success,
              let menuBar = menuBarObj as! AXUIElement? else {
            fallbackAppleScript(shouldBeMuted: shouldBeMuted)
            return
        }

        var menuBarItemsObj: AnyObject?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &menuBarItemsObj) == .success,
              let menuBarItems = menuBarItemsObj as? [AXUIElement] else {
            fallbackAppleScript(shouldBeMuted: shouldBeMuted)
            return
        }

        for item in menuBarItems {
            var titleObj: AnyObject?
            AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleObj)
            if let title = titleObj as? String, title == "Video" {
                var menuObj: AnyObject?
                if AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &menuObj) == .success,
                   let subMenus = menuObj as? [AXUIElement], let videoMenu = subMenus.first {
                    var itemsObj: AnyObject?
                    if AXUIElementCopyAttributeValue(videoMenu, kAXChildrenAttribute as CFString, &itemsObj) == .success,
                       let videoItems = itemsObj as? [AXUIElement], let muteItem = videoItems.first {

                        var enabledObj: AnyObject?
                        AXUIElementCopyAttributeValue(muteItem, kAXEnabledAttribute as CFString, &enabledObj)
                        let isCallActive = (enabledObj as? Bool) ?? false
                        guard isCallActive else { return }

                        var markObj: AnyObject?
                        AXUIElementCopyAttributeValue(muteItem, "AXMenuItemMarkChar" as CFString, &markObj)
                        let isCurrentlyMuted = (markObj as? String) == "✓"

                        if shouldBeMuted != isCurrentlyMuted {
                            let actionResult = AXUIElementPerformAction(muteItem, kAXPressAction as CFString)
                            if actionResult != .success {
                                fallbackAppleScript(shouldBeMuted: shouldBeMuted)
                            } else {
                                NSLog("[MicMute] Synchronized FaceTime mute state: now \(shouldBeMuted ? "muted" : "unmuted")")
                            }
                        }
                        return
                    }
                }
            }
        }

        fallbackAppleScript(shouldBeMuted: shouldBeMuted)
    }

    private func fallbackAppleScript(shouldBeMuted: Bool) {
        let script = """
        tell application "System Events"
            if exists (process "FaceTime") then
                tell process "FaceTime"
                    if exists (menu "Video" of menu bar 1) then
                        set muteItem to menu item 1 of menu "Video" of menu bar 1
                        if enabled of muteItem then
                            set isMuted to (value of attribute "AXMenuItemMarkChar" of muteItem is "✓")
                            if \(shouldBeMuted ? "true" : "false") is not isMuted then
                                click muteItem
                            end if
                        end if
                    end if
                end tell
            end if
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                NSLog("[MicMute] FaceTime AppleScript fallback error: \(error)")
            }
        }
    }
}

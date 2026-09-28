import Foundation
import AppKit
import ApplicationServices

/// Synchronizes mute/unmute state bidirectionally with active Apple FaceTime calls.
public final class FaceTimeSyncManager {
    public static let shared = FaceTimeSyncManager()

    private let syncQueue = DispatchQueue(label: "com.janred.MicMute.faceTimeSync", qos: .utility)
    private var timerSource: DispatchSourceTimer?

    // Tracking state
    private var wasCallActive: Bool = false
    private var lastKnownFaceTimeMuted: Bool? = nil
    private var isPerformingOutgoingSync: Bool = false

    private init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring

    public func startMonitoring() {
        stopMonitoring()

        let timer = DispatchSource.makeTimerSource(queue: syncQueue)
        // Poll every 350ms for responsive bidirectional synchronization with minimal CPU usage (<0.01%)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(350))
        timer.setEventHandler { [weak self] in
            self?.pollFaceTimeState()
        }
        timer.resume()
        self.timerSource = timer
    }

    public func stopMonitoring() {
        timerSource?.cancel()
        timerSource = nil
    }

    // MARK: - Outgoing Sync (MicMute -> FaceTime)

    /// Synchronizes FaceTime call mute state with the requested MicMute state.
    public func syncFaceTimeMute(shouldBeMuted: Bool) {
        guard SettingsStore.shared.faceTimeSyncEnabled else { return }

        syncQueue.async { [weak self] in
            guard let self = self else { return }
            self.lastKnownFaceTimeMuted = shouldBeMuted
            self.isPerformingOutgoingSync = true
            self.performOutgoingSync(shouldBeMuted: shouldBeMuted)
            // Clear outgoing flag shortly after action completes
            self.syncQueue.asyncAfter(deadline: .now() + .milliseconds(400)) {
                self.isPerformingOutgoingSync = false
            }
        }
    }

    private func performOutgoingSync(shouldBeMuted: Bool) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.FaceTime")
        guard let ft = apps.first else { return }

        if let (isCallActive, isFaceTimeMuted, muteItem) = queryFaceTimeState(pid: ft.processIdentifier) {
            guard isCallActive else { return }
            if isFaceTimeMuted != shouldBeMuted {
                let actionResult = AXUIElementPerformAction(muteItem, kAXPressAction as CFString)
                if actionResult != .success {
                    fallbackAppleScript(shouldBeMuted: shouldBeMuted)
                } else {
                    NSLog("[MicMute] Synchronized outgoing mute state to FaceTime: now \(shouldBeMuted ? "muted" : "unmuted")")
                }
            }
        } else {
            fallbackAppleScript(shouldBeMuted: shouldBeMuted)
        }
    }

    // MARK: - Incoming Sync & Call Protection (FaceTime -> MicMute)

    private func pollFaceTimeState() {
        guard SettingsStore.shared.faceTimeSyncEnabled else { return }
        guard !isPerformingOutgoingSync else { return }

        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.FaceTime")
        guard let ft = apps.first else {
            if wasCallActive {
                wasCallActive = false
                lastKnownFaceTimeMuted = nil
            }
            return
        }

        guard let (isCallActive, isFaceTimeMuted, muteItem) = queryFaceTimeState(pid: ft.processIdentifier) else {
            return
        }

        // Case 1: Transition into an active call (Call Just Started / Joined)
        if !wasCallActive && isCallActive {
            wasCallActive = true
            let systemIsMuted = AudioEngine.shared.isMuted

            // Protection: If user was ALREADY muted in MicMute before joining, enforce mute on FaceTime!
            if systemIsMuted {
                if !isFaceTimeMuted {
                    AXUIElementPerformAction(muteItem, kAXPressAction as CFString)
                    NSLog("[MicMute] Enforced pre-existing system mute onto newly joined FaceTime call.")
                }
                lastKnownFaceTimeMuted = true
            } else {
                if isFaceTimeMuted {
                    // Call started muted on FaceTime; synchronize system CoreAudio mute to match
                    DispatchQueue.main.async {
                        AudioEngine.shared.setMute(true, syncFaceTime: false)
                    }
                    lastKnownFaceTimeMuted = true
                } else {
                    lastKnownFaceTimeMuted = false
                }
            }
            return
        }

        // Case 2: Transition out of an active call (Call Ended)
        if wasCallActive && !isCallActive {
            wasCallActive = false
            lastKnownFaceTimeMuted = nil
            return
        }

        // Case 3: Call is ongoing, monitor for manual mute/unmute actions inside FaceTime
        if isCallActive {
            if let lastMuted = lastKnownFaceTimeMuted {
                if isFaceTimeMuted != lastMuted {
                    // User manually clicked Mute/Unmute in FaceTime (or used FaceTime menu/shortcut)!
                    lastKnownFaceTimeMuted = isFaceTimeMuted
                    NSLog("[MicMute] Detected manual mute toggle inside FaceTime: now \(isFaceTimeMuted ? "muted" : "unmuted"). Syncing system audio.")

                    DispatchQueue.main.async {
                        // Update system CoreAudio volume and other apps without re-triggering FaceTime
                        AudioEngine.shared.setMute(isFaceTimeMuted, syncFaceTime: false)
                    }
                }
            } else {
                lastKnownFaceTimeMuted = isFaceTimeMuted
            }
        }
    }

    // MARK: - State Inspection Helper

    private func queryFaceTimeState(pid: pid_t) -> (isCallActive: Bool, isMuted: Bool, muteItem: AXUIElement)? {
        let appElement = AXUIElementCreateApplication(pid)

        var menuBarObj: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarObj) == .success,
              let menuBar = menuBarObj as! AXUIElement? else { return nil }

        var menuBarItemsObj: AnyObject?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &menuBarItemsObj) == .success,
              let menuBarItems = menuBarItemsObj as? [AXUIElement] else { return nil }

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

                        var markObj: AnyObject?
                        AXUIElementCopyAttributeValue(muteItem, "AXMenuItemMarkChar" as CFString, &markObj)
                        let isMuted = (markObj as? String) == "✓"

                        return (isCallActive, isMuted, muteItem)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Fallback AppleScript

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

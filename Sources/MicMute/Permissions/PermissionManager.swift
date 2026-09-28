import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
import Combine

public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public private(set) var isAccessibilityGranted: Bool = false
    @Published public private(set) var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @Published public private(set) var isLaunchAtLoginEnabled: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    private init() {
        checkPermissions()
        startActiveTimer()
        setupNotificationListeners()
    }

    deinit {
        timer?.invalidate()
    }

    public func startActiveTimer() {
        timer?.invalidate()
        // Poll every 1 second so permission toggles in System Settings are detected dynamically
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermissions()
        }
    }

    public func checkPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let axTrusted = AXIsProcessTrustedWithOptions(options)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let loginEnabled = queryLaunchAtLoginStatus()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isAccessibilityGranted != axTrusted {
                self.isAccessibilityGranted = axTrusted
                if axTrusted {
                    HotkeyManager.shared.rebindHotkeys()
                }
            }

            if self.microphoneStatus != micStatus {
                self.microphoneStatus = micStatus
            }

            if self.isLaunchAtLoginEnabled != loginEnabled {
                self.isLaunchAtLoginEnabled = loginEnabled
                SettingsStore.shared.launchAtLogin = loginEnabled
            }
        }
    }

    private func setupNotificationListeners() {
        // Refresh when application or window gains focus
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkPermissions()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] _ in
                self?.checkPermissions()
            }
            .store(in: &cancellables)
    }

    // MARK: - Accessibility

    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettingsAccessibility()
    }

    public func openSystemSettingsAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Microphone

    public func requestMicrophonePermission(completion: ((Bool) -> Void)? = nil) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.checkPermissions()
                    completion?(granted)
                }
            }
        case .authorized:
            completion?(true)
        case .denied, .restricted:
            openSystemSettingsMicrophone()
            completion?(false)
        @unknown default:
            completion?(false)
        }
    }

    public func openSystemSettingsMicrophone() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Open at Login

    private func queryLaunchAtLoginStatus() -> Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled || status == .requiresApproval {
                return true
            }
        }
        return checkAppleScriptLoginItem()
    }

    private func checkAppleScriptLoginItem() -> Bool {
        let appName = "MicMute"
        let script = "tell application \"System Events\" to (exists (first login item whose name is \"\(appName)\"))"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                return result.booleanValue
            }
        }
        return false
    }

    public func setLaunchAtLogin(enabled: Bool) {
        var smSuccess = false
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                    smSuccess = true
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                    smSuccess = true
                }
            } catch {
                NSLog("[MicMute] SMAppService error: \(error). Falling back to AppleScript.")
            }
        }

        if !smSuccess {
            setAppleScriptLoginItem(enabled: enabled)
        }

        checkPermissions()
    }

    private func setAppleScriptLoginItem(enabled: Bool) {
        let appName = "MicMute"
        let appPath = Bundle.main.bundlePath
        let script: String
        if enabled {
            script = "tell application \"System Events\" to make login item at end with properties {path:\"\(appPath)\", hidden:false, name:\"\(appName)\"}"
        } else {
            script = "tell application \"System Events\" to delete (every login item whose name is \"\(appName)\")"
        }
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                NSLog("[MicMute] AppleScript login item error: \(error)")
            }
        }
    }

    public func openSystemSettingsLoginItems() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

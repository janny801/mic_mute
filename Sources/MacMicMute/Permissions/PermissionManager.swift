import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import Combine

public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public private(set) var isAccessibilityGranted: Bool = false
    @Published public private(set) var microphoneStatus: AVAuthorizationStatus = .notDetermined

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
        DispatchQueue.main.async {
            // Check Accessibility
            let axTrusted = AXIsProcessTrusted()
            if self.isAccessibilityGranted != axTrusted {
                self.isAccessibilityGranted = axTrusted
                if axTrusted {
                    HotkeyManager.shared.rebindHotkeys()
                }
            }

            // Check Microphone
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if self.microphoneStatus != micStatus {
                self.microphoneStatus = micStatus
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
}

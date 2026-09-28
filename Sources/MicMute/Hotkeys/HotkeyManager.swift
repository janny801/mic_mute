import Foundation
import AppKit
import Carbon
import Combine

public final class HotkeyManager: ObservableObject {
    public static let shared = HotkeyManager()

    // Carbon hotkey state
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonEventHandler: EventHandlerRef?
    private let hotKeySignature = OSType(0x4D49434B) // 'MICK'
    private let hotKeyIDValue: UInt32 = 1

    // CGEventTap state
    private var eventTapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDownActive: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeSettings()
        registerHotkeys()
    }

    deinit {
        unregisterHotkeys()
    }

    private func observeSettings() {
        // Observe key combo changes
        SettingsStore.shared.$keyCombo
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebindHotkeys()
            }
            .store(in: &cancellables)

        // Observe mode changes
        SettingsStore.shared.$mode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMode in
                if newMode == .pushToTalk {
                    // When entering push-to-talk, mute by default
                    AudioEngine.shared.setMute(true)
                }
                self?.rebindHotkeys()
            }
            .store(in: &cancellables)

        // Observe accessibility changes
        PermissionManager.shared.$isAccessibilityGranted
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isGranted in
                if isGranted {
                    self?.setupEventTap()
                }
            }
            .store(in: &cancellables)
    }

    public func rebindHotkeys() {
        unregisterHotkeys()
        registerHotkeys()
    }

    public func registerHotkeys() {
        // 1. Try to set up CGEventTap first (supports both KeyDown and KeyUp, ideal for Push-to-Talk)
        setupEventTap()

        // 2. Also register Carbon HotKey as a fallback for Toggle mode
        setupCarbonHotkey()
    }

    public func unregisterHotkeys() {
        removeEventTap()
        removeCarbonHotkey()
    }

    // MARK: - Carbon HotKey (Fallback & Toggle)

    private func setupCarbonHotkey() {
        removeCarbonHotkey()

        let combo = SettingsStore.shared.keyCombo
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyIDValue)

        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )

        guard status == noErr else {
            NSLog("[MicMute] Failed to register Carbon hotkey, status: \(status)")
            return
        }

        var eventSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, eventRef, userData) -> OSStatus in
                guard let userData = userData, let eventRef = eventRef else {
                    return CallNextEventHandler(nextHandler, eventRef)
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let kind = GetEventKind(eventRef)

                // If event tap is already active and handling events, avoid double-firing
                if manager.eventTapPort != nil && PermissionManager.shared.isAccessibilityGranted {
                    return CallNextEventHandler(nextHandler, eventRef)
                }

                DispatchQueue.main.async {
                    if kind == UInt32(kEventHotKeyPressed) {
                        manager.handleKeyDown()
                    } else if kind == UInt32(kEventHotKeyReleased) {
                        manager.handleKeyUp()
                    }
                }

                return noErr
            },
            2,
            &eventSpecs,
            selfPtr,
            &carbonEventHandler
        )

        if handlerStatus != noErr {
            NSLog("[MicMute] Failed to install Carbon event handler, status: \(handlerStatus)")
        }
    }

    private func removeCarbonHotkey() {
        if let ref = carbonHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonHotKeyRef = nil
        }
        if let handler = carbonEventHandler {
            RemoveEventHandler(handler)
            carbonEventHandler = nil
        }
    }

    // MARK: - CGEventTap (Full interception with KeyDown + KeyUp)

    private func setupEventTap() {
        removeEventTap()

        guard AXIsProcessTrusted() else {
            return
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = manager.eventTapPort {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                if type == .keyDown || type == .keyUp {
                    let handled = manager.processCGEvent(event, type: type)
                    if handled {
                        // Suppress event from propagating so shortcut isn't typed into active apps
                        return nil
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        )

        guard let tapPort = tap else {
            NSLog("[MicMute] CGEvent.tapCreate returned nil")
            return
        }

        self.eventTapPort = tapPort
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tapPort, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tapPort, enable: true)
    }

    private func removeEventTap() {
        if let port = eventTapPort {
            CGEvent.tapEnable(tap: port, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                runLoopSource = nil
            }
            CFMachPortInvalidate(port)
            eventTapPort = nil
        }
    }

    // MARK: - Event Processing

    private func processCGEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        let targetCombo = SettingsStore.shared.keyCombo
        let eventKeyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))

        guard eventKeyCode == targetCombo.keyCode else {
            return false
        }

        // Match modifiers
        let currentFlags = event.flags
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let relevantFlags = currentFlags.intersection(mask)
        let expectedFlags = targetCombo.cgEventFlags

        guard relevantFlags == expectedFlags else {
            return false
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if type == .keyDown {
            if isRepeat {
                // Ignore key repeat events
                return true
            }
            handleKeyDown()
            return true
        } else if type == .keyUp {
            handleKeyUp()
            return true
        }

        return false
    }

    private func handleKeyDown() {
        let mode = SettingsStore.shared.mode
        switch mode {
        case .toggle:
            AudioEngine.shared.toggleMute()
        case .pushToTalk:
            if !isKeyDownActive {
                isKeyDownActive = true
                AudioEngine.shared.setMute(false) // Unmute on press
            }
        }
    }

    private func handleKeyUp() {
        let mode = SettingsStore.shared.mode
        switch mode {
        case .toggle:
            break
        case .pushToTalk:
            if isKeyDownActive {
                isKeyDownActive = false
                AudioEngine.shared.setMute(true) // Mute on release
            }
        }
    }
}

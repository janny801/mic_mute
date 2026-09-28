import AppKit
import Combine
import CoreAudio

public final class MenuBarController: NSObject {
    public static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    // Menu items to update dynamically
    private var statusMenuItem: NSMenuItem?
    private var modeMenuItem: NSMenuItem?
    private var deviceMenuItem: NSMenuItem?
    private var permissionsMenuItem: NSMenuItem?

    private var cancellables = Set<AnyCancellable>()

    public override init() {
        super.init()
    }

    public func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item

        setupMenu()
        observeState()
        updateUI()
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 1. Status Item (clickable to toggle)
        let statusItem = NSMenuItem(
            title: "Microphone: Active",
            action: #selector(toggleMuteClicked),
            keyEquivalent: ""
        )
        statusItem.target = self
        menu.addItem(statusItem)
        self.statusMenuItem = statusItem

        // 2. Mode Item
        let modeItem = NSMenuItem(
            title: "Mode: Toggle",
            action: #selector(openSettingsClicked),
            keyEquivalent: ""
        )
        modeItem.target = self
        menu.addItem(modeItem)
        self.modeMenuItem = modeItem

        // 3. Current Device & Switching Submenu
        let deviceItem = NSMenuItem(
            title: "Microphone",
            action: nil,
            keyEquivalent: ""
        )
        deviceItem.submenu = NSMenu()
        menu.addItem(deviceItem)
        self.deviceMenuItem = deviceItem

        // 4. Permissions Status Item
        let permItem = NSMenuItem(
            title: "Permissions: Checking...",
            action: #selector(openSettingsClicked),
            keyEquivalent: ""
        )
        permItem.target = self
        menu.addItem(permItem)
        self.permissionsMenuItem = permItem

        menu.addItem(NSMenuItem.separator())

        // 4. Preferences / Settings...
        let prefsItem = NSMenuItem(
            title: "Preferences / Settings...",
            action: #selector(openSettingsClicked),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Quit
        let quitItem = NSMenuItem(
            title: "Quit MicMute",
            action: #selector(quitAppClicked),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
        self.statusItem?.menu = menu
    }

    private func observeState() {
        // Observe mute state
        AudioEngine.shared.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)

        // Observe device name
        AudioEngine.shared.$deviceName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)

        // Observe available devices
        AudioEngine.shared.$availableInputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)

        // Observe mode
        SettingsStore.shared.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)

        // Observe keyCombo
        SettingsStore.shared.$keyCombo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)

        // Observe permissions
        PermissionManager.shared.$isAccessibilityGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)

        PermissionManager.shared.$microphoneStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)
    }

    public func updateUI() {
        guard let button = statusItem?.button else { return }

        let isMuted = AudioEngine.shared.isMuted
        let deviceName = AudioEngine.shared.deviceName
        let mode = SettingsStore.shared.mode
        let keyCombo = SettingsStore.shared.keyCombo

        // 1. Update Menu Bar Icon
        let symbolName = isMuted ? "mic.slash.fill" : "mic.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)

        if let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: isMuted ? "Microphone Muted" : "Microphone Active") {
            let symbolImage = baseImage.withSymbolConfiguration(config) ?? baseImage
            symbolImage.isTemplate = true
            button.image = symbolImage
            button.imagePosition = .imageLeading
        }

        // Clear status text label in menu bar so user can immediately see it
        button.title = isMuted ? " Muted" : " Active"

        // Tooltip
        let actionDesc = isMuted ? "Click or press \(keyCombo.displayString) to unmute" : "Click or press \(keyCombo.displayString) to mute"
        button.toolTip = "\(isMuted ? "Microphone Muted" : "Microphone Active") (\(actionDesc))"

        // 2. Update Menu Items
        if let statusMenuItem = self.statusMenuItem {
            if isMuted {
                statusMenuItem.title = "Microphone: Muted  (Click to Unmute)"
                statusMenuItem.image = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: nil)
            } else {
                statusMenuItem.title = "Microphone: Active  (Click to Mute)"
                statusMenuItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
            }
        }

        if let modeMenuItem = self.modeMenuItem {
            switch mode {
            case .toggle:
                modeMenuItem.title = "Mode: Toggle (\(keyCombo.displayString))"
            case .pushToTalk:
                modeMenuItem.title = "Mode: Push-to-Talk (Hold \(keyCombo.displayString))"
            }
            modeMenuItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        }

        if let deviceMenuItem = self.deviceMenuItem {
            deviceMenuItem.title = "Input: \(deviceName)"
            deviceMenuItem.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)

            // Populate device switching submenu
            let submenu = NSMenu()
            for dev in AudioEngine.shared.availableInputDevices {
                let item = NSMenuItem(
                    title: dev.name,
                    action: #selector(deviceSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = dev.id
                item.state = (dev.id == AudioEngine.shared.defaultDeviceID) ? .on : .off
                submenu.addItem(item)
            }
            deviceMenuItem.submenu = submenu
        }

        // 4. Update Permissions Status Item
        if let permissionsMenuItem = self.permissionsMenuItem {
            let isAxGranted = PermissionManager.shared.isAccessibilityGranted
            let isMicGranted = (PermissionManager.shared.microphoneStatus == .authorized)

            if isAxGranted && isMicGranted {
                permissionsMenuItem.title = "Permissions: Granted ✓"
                permissionsMenuItem.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            } else if !isAxGranted && !isMicGranted {
                permissionsMenuItem.title = "⚠️ Permissions Required (Mic & Accessibility)"
                permissionsMenuItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            } else if !isAxGranted {
                permissionsMenuItem.title = "⚠️ Accessibility Permission Required"
                permissionsMenuItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            } else {
                permissionsMenuItem.title = "⚠️ Microphone Permission Required"
                permissionsMenuItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleMuteClicked() {
        AudioEngine.shared.toggleMute()
    }

    @objc private func openSettingsClicked() {
        SettingsWindowController.shared.showWindow()
    }

    @objc private func quitAppClicked() {
        NSApp.terminate(nil)
    }

    @objc private func deviceSelected(_ sender: NSMenuItem) {
        if let deviceID = sender.representedObject as? AudioDeviceID {
            AudioEngine.shared.selectDevice(deviceID)
        }
    }
}

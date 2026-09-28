import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var audioEngine = AudioEngine.shared
    @ObservedObject var permissions = PermissionManager.shared
    @ObservedObject var micTest = MicTestManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    micDeviceAndTestSection
                    operatingModeSection
                    hotkeySection
                    audioFeedbackSection
                    integrationsSection
                    permissionsSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
            Divider()
            footerView
        }
        .frame(width: 530, height: 720)
        .onAppear {
            permissions.checkPermissions()
            audioEngine.refreshInputDevices()
        }
        .onDisappear {
            micTest.stopAll()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(audioEngine.isMuted ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: audioEngine.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(audioEngine.isMuted ? .red : .green)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("MicMute")
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 6) {
                    Circle()
                        .fill(audioEngine.isMuted ? Color.red : Color.green)
                        .frame(width: 8, height: 8)

                    Text(audioEngine.isMuted ? "Microphone Muted" : "Microphone Active")
                        .font(.subheadline)
                        .foregroundColor(audioEngine.isMuted ? .red : .green)
                        .fontWeight(.medium)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(audioEngine.deviceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: {
                audioEngine.toggleMute()
            }) {
                Label(
                    audioEngine.isMuted ? "Unmute" : "Mute",
                    systemImage: audioEngine.isMuted ? "mic.fill" : "mic.slash.fill"
                )
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .tint(audioEngine.isMuted ? .green : .red)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Mic Device & Live Test Section
    private var micDeviceAndTestSection: some View {
        GroupBox(label: Label("Microphone Input & Test", systemImage: "mic.badge.waveform")) {
            VStack(alignment: .leading, spacing: 14) {
                // Device Selector
                HStack {
                    Text("Input Device:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Picker("", selection: Binding(
                        get: { audioEngine.defaultDeviceID },
                        set: { audioEngine.selectDevice($0) }
                    )) {
                        ForEach(audioEngine.availableInputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }

                Divider()

                // Live VU Meter & Audio Test
                VStack(alignment: .leading, spacing: 8) {
                    Text("Volume Level & Test:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VolumeMeterView()
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Operating Mode
    private var operatingModeSection: some View {
        GroupBox(label: Label("Operating Mode", systemImage: "slider.horizontal.3")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(AppMuteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(settings.mode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.mode == .pushToTalk && !permissions.isAccessibilityGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Push-to-talk requires Accessibility permission to detect key release.")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                        Button("Open Settings") {
                            permissions.requestAccessibilityPermission()
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    // MARK: - Hotkey Section
    private var hotkeySection: some View {
        GroupBox(label: Label("Global Hotkey", systemImage: "keyboard")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Shortcut:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    HotkeyRecorderView()
                }

                Text("Works system-wide across all apps (FaceTime, Zoom, Teams, Discord, Games) even when running in background.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    // MARK: - Audio Feedback
    private var audioFeedbackSection: some View {
        GroupBox(label: Label("Audio Feedback", systemImage: "speaker.wave.2")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Play sound cue when state changes", isOn: $settings.audioFeedbackEnabled)

                if settings.audioFeedbackEnabled {
                    HStack(spacing: 16) {
                        HStack {
                            Text("Unmuted:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Pop")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Button(action: {
                                SoundCueManager.shared.playSound(named: "Pop")
                            }) {
                                Image(systemName: "play.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Preview Unmute Sound")
                        }

                        Divider()
                            .frame(height: 16)

                        HStack {
                            Text("Muted:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Tink")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Button(action: {
                                SoundCueManager.shared.playSound(named: "Tink")
                            }) {
                                Image(systemName: "play.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Preview Mute Sound")
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    // MARK: - Call Integrations Section
    private var integrationsSection: some View {
        GroupBox(label: Label("Call Integrations", systemImage: "phone.badge.waveform")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Sync with Apple FaceTime calls", isOn: $settings.faceTimeSyncEnabled)

                Text("Automatically synchronizes FaceTime's call mute switch with your global MicMute hotkey.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    // MARK: - Permissions Section
    private var permissionsSection: some View {
        GroupBox(label: Label("System Permissions", systemImage: "lock.shield")) {
            VStack(spacing: 12) {
                // Accessibility
                HStack {
                    Image(systemName: permissions.isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(permissions.isAccessibilityGranted ? .green : .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(permissions.isAccessibilityGranted ? "Active — global keyup & push-to-talk enabled" : "Recommended for push-to-talk release detection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if permissions.isAccessibilityGranted {
                        Text("Granted")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    } else {
                        Button("Open Settings") {
                            permissions.requestAccessibilityPermission()
                        }
                        .controlSize(.small)
                    }

                    // 3 Vertical Dots Menu
                    Menu {
                        Button("Open in System Settings...") {
                            permissions.openSystemSettingsAccessibility()
                        }
                        Button("Check Status Again") {
                            permissions.checkPermissions()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 24, height: 24)
                    .help("Open Accessibility Settings")
                }

                Divider()

                // Microphone
                HStack {
                    let isMicGranted = (permissions.microphoneStatus == .authorized)
                    Image(systemName: isMicGranted ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundColor(isMicGranted ? .green : .blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microphone Access")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(isMicGranted ? "Authorized — full system audio control" : "Used to monitor & manage input devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isMicGranted {
                        Text("Granted")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    } else {
                        Button(permissions.microphoneStatus == .notDetermined ? "Authorize" : "Open Settings") {
                            permissions.requestMicrophonePermission()
                        }
                        .controlSize(.small)
                    }

                    // 3 Vertical Dots Menu
                    Menu {
                        Button("Open in System Settings...") {
                            permissions.openSystemSettingsMicrophone()
                        }
                        Button("Check Status Again") {
                            permissions.checkPermissions()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 24, height: 24)
                    .help("Open Microphone Settings")
                }

                Divider()

                // Open at Login
                HStack {
                    Image(systemName: permissions.isLaunchAtLoginEnabled ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundColor(permissions.isLaunchAtLoginEnabled ? .green : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open at Login")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(permissions.isLaunchAtLoginEnabled ? "Enabled — launches automatically when you log into your Mac" : "Automatically launch MicMute when you log into your Mac")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { permissions.isLaunchAtLoginEnabled },
                        set: { permissions.setLaunchAtLogin(enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()

                    // 3 Vertical Dots Menu
                    Menu {
                        Button("Open in System Settings...") {
                            permissions.openSystemSettingsLoginItems()
                        }
                        Button("Check Status Again") {
                            permissions.checkPermissions()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 24, height: 24)
                    .help("Open Login Items Settings")
                }

                let isMicGranted = (permissions.microphoneStatus == .authorized)
                if !permissions.isAccessibilityGranted || !isMicGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("If permission is already turned on in macOS System Settings, toggle the switch off and on once to refresh.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Button("Reset Defaults") {
                settings.resetToDefaults()
            }
            .controlSize(.small)

            Spacer()

            Button("Quit MicMute") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
            .foregroundColor(.red)

            Button("Done") {
                SettingsWindowController.shared.closeWindow()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

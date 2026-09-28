# MicMute (Native macOS Menu Bar Utility)

A lightweight, native macOS menu bar utility built in **Swift and SwiftUI / AppKit** for system-level microphone muting and toggling with low-latency audio feedback, global push-to-talk support, and a preferences UI.

---

## Features

1. **Persistent Menu Bar Status Item**
   - Displays real-time microphone status in the macOS menu bar:
     - 🎙️ **Active / Unmuted**: Microphone icon with "Active" label (`mic.fill`).
     - 🔇 **Muted**: Slashed microphone icon with "Muted" label (`mic.slash.fill`).
   - Clickable dropdown menu:
     - Current mic state indicator (click to toggle instantly).
     - Operating mode indicator (`Toggle` or `Push-to-Talk`).
     - Default audio input device name.
     - "Preferences / Settings..." (`⌘,`).
     - "Quit MicMute" (`⌘Q`).

2. **Global Hotkey & Interception**
   - **Default Hotkey**: `Command + \` (`⌘\`).
   - Works globally across macOS, regardless of which application (FaceTime, Zoom, Teams, Discord, games, browser) has focus.
   - Suppresses shortcut keystrokes so typing into text editors isn't disrupted.

3. **Operating Modes**
   - **Toggle Mode (Default)**: Press `⌘\` once to mute, press again to unmute.
   - **Push-to-Talk Mode**: The microphone stays muted by default and unmutes only while the assigned key is actively held down; it automatically re-mutes when released.

4. **Low-Latency Audio Cues**
   - Plays distinct system sound cues through your default audio output device without blocking or lagging the mic toggle:
     - **Unmuted**: High-tone cheerful cue (`Pop`).
     - **Muted**: Low-tone subtle cue (`Tink`).
   - Can be enabled or disabled in Preferences, with instant sound preview buttons.

5. **CoreAudio Input Engine**
   - Directly controls the default macOS input device using `CoreAudio` APIs.
   - Sets hardware mute (`kAudioDevicePropertyMute`) if supported by the input device.
   - Adjusts input volume scalar (`kAudioDevicePropertyVolumeScalar`) to `0.0` when muting and smoothly restores the previous gain when unmuting.
   - Dynamically listens to system audio device changes (e.g. plugging in AirPods or a USB microphone) and updates automatically.

6. **Native Preferences & Settings Window**
   - Clean SwiftUI preferences window automatically opened on launch and accessible from the menu bar item.
   - **Interactive Hotkey Recorder**: Click to record custom shortcut combinations (handles modifier keys + keycodes).
   - **Mode Selection**: Switch between Toggle and Push-to-Talk.
   - **Live Mic Controls**: Instant Mute/Unmute toggle button.
   - **Permissions Status & Onboarding**: Clear status indicators for macOS Accessibility and Microphone permissions, with direct links to macOS System Settings.

---

## Project Structure

```
mac-mic-mute/
├── Package.swift                    # Swift Package Manager manifest
├── Makefile                         # Convenient build and run commands
├── scripts/
│   └── build_app.sh                 # Builds release/debug MicMute.app bundle with icons & ad-hoc signing
├── Resources/
│   ├── Info.plist                   # App bundle metadata and permissions
│   └── AppIcon.icns                 # Multi-resolution macOS application icon
└── Sources/
    └── MicMute/
        ├── main.swift               # Application entry point
        ├── App/
        │   └── AppDelegate.swift    # App lifecycle and initial window presentation
        ├── CoreAudio/
        │   ├── AudioEngine.swift    # Hardware mute, volume scalar control, and device switching
        │   └── MicTestManager.swift # Live audio input testing and volume metering
        ├── Sound/
        │   └── SoundCueManager.swift# Low-latency audio cues (Pop / Tink)
        ├── Hotkeys/
        │   ├── KeyCombo.swift       # Shortcut model, modifiers, and UCKeyTranslate layout mapping
        │   └── HotkeyManager.swift  # CGEventTap + Carbon hotkey handling for Toggle & Push-to-Talk
        ├── Settings/
        │   └── SettingsStore.swift  # UserDefaults persistence and reactive state
        ├── Permissions/
        │   └── PermissionManager.swift # Accessibility & Microphone permission handling
        └── UI/
            ├── MenuBarController.swift      # NSStatusItem and dropdown menu management
            ├── SettingsWindowController.swift # NSWindow management for Preferences
            ├── SettingsView.swift           # SwiftUI Preferences UI
            ├── VolumeMeterView.swift        # Real-time LED-style audio VU meter
            └── HotkeyRecorderView.swift     # Interactive key recording view
```

---

## How to Build & Run

### Quick Start with Make
```bash
# Build the release .app bundle
make

# Launch the app
make run

# Clean build artifacts
make clean
```

### Or using the build script
```bash
./scripts/build_app.sh release
open build/MicMute.app
```

---

## Permissions & Onboarding

1. **Accessibility Permission (Recommended for Push-to-Talk):**
   - Required by macOS for `CGEventTap` to detect when the hotkey is released in Push-to-Talk mode.
   - Can be granted with one click directly in the Preferences window ("Grant Permission"), which prompts macOS and opens **System Settings > Privacy & Security > Accessibility**.
   - *Note*: In Toggle Mode, Carbon hotkeys function even before Accessibility is enabled!

2. **Microphone Permission:**
   - Authorizes the app to monitor and control system input audio devices.
   - Can be requested directly inside the Preferences window.

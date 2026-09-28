import Foundation
import Combine

public enum AppMuteMode: String, CaseIterable, Identifiable, Codable {
    case toggle = "toggle"
    case pushToTalk = "pushToTalk"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .toggle:
            return "Toggle Mode"
        case .pushToTalk:
            return "Push-to-Talk Mode"
        }
    }

    public var description: String {
        switch self {
        case .toggle:
            return "Press hotkey once to mute, press again to unmute."
        case .pushToTalk:
            return "Microphone is muted by default. Unmutes only while holding the hotkey, then mutes when released."
        }
    }
}

public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let muteMode = "muteMode"
        static let keyCombo = "keyCombo"
        static let audioFeedbackEnabled = "audioFeedbackEnabled"
        static let muteSoundName = "muteSoundName"
        static let unmuteSoundName = "unmuteSoundName"
        static let launchAtLogin = "launchAtLogin"
        static let faceTimeSyncEnabled = "faceTimeSyncEnabled"
    }

    @Published public var mode: AppMuteMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Keys.muteMode)
        }
    }

    @Published public var keyCombo: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(keyCombo) {
                defaults.set(data, forKey: Keys.keyCombo)
            }
        }
    }

    @Published public var audioFeedbackEnabled: Bool {
        didSet {
            defaults.set(audioFeedbackEnabled, forKey: Keys.audioFeedbackEnabled)
        }
    }

    @Published public var muteSoundName: String {
        didSet {
            defaults.set(muteSoundName, forKey: Keys.muteSoundName)
        }
    }

    @Published public var unmuteSoundName: String {
        didSet {
            defaults.set(unmuteSoundName, forKey: Keys.unmuteSoundName)
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    @Published public var faceTimeSyncEnabled: Bool {
        didSet {
            defaults.set(faceTimeSyncEnabled, forKey: Keys.faceTimeSyncEnabled)
        }
    }

    public init() {
        // Mode
        if let modeRaw = defaults.string(forKey: Keys.muteMode),
           let savedMode = AppMuteMode(rawValue: modeRaw) {
            self.mode = savedMode
        } else {
            self.mode = .toggle
        }

        // Key Combo
        if let data = defaults.data(forKey: Keys.keyCombo),
           let savedCombo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            self.keyCombo = savedCombo
        } else {
            self.keyCombo = .default
        }

        // Audio feedback
        if defaults.object(forKey: Keys.audioFeedbackEnabled) != nil {
            self.audioFeedbackEnabled = defaults.bool(forKey: Keys.audioFeedbackEnabled)
        } else {
            self.audioFeedbackEnabled = true
        }

        // Sound names
        self.muteSoundName = defaults.string(forKey: Keys.muteSoundName) ?? "Tink"
        self.unmuteSoundName = defaults.string(forKey: Keys.unmuteSoundName) ?? "Pop"

        // Launch at login
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        // FaceTime Sync
        if defaults.object(forKey: Keys.faceTimeSyncEnabled) != nil {
            self.faceTimeSyncEnabled = defaults.bool(forKey: Keys.faceTimeSyncEnabled)
        } else {
            self.faceTimeSyncEnabled = true
        }
    }

    public func resetToDefaults() {
        self.mode = .toggle
        self.keyCombo = .default
        self.audioFeedbackEnabled = true
        self.muteSoundName = "Tink"
        self.unmuteSoundName = "Pop"
        self.faceTimeSyncEnabled = true
    }
}

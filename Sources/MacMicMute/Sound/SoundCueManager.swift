import Foundation
import AppKit
import AudioToolbox

public final class SoundCueManager {
    public static let shared = SoundCueManager()

    private let soundQueue = DispatchQueue(label: "com.janred.MacMicMute.soundQueue", qos: .userInteractive)

    // Pre-cached sounds for minimal latency
    private var cachedSounds: [String: NSSound] = [:]

    private init() {
        preloadCommonSounds()
    }

    private func preloadCommonSounds() {
        let names = ["Pop", "Tink", "Funk", "Basso", "Bottle", "Hero", "Ping", "Submarine"]
        for name in names {
            if let sound = NSSound(named: NSSound.Name(name)) {
                cachedSounds[name] = sound
            } else {
                // Fallback to /System/Library/Sounds/<name>.aiff
                let path = "/System/Library/Sounds/\(name).aiff"
                if let sound = NSSound(contentsOfFile: path, byReference: true) {
                    cachedSounds[name] = sound
                }
            }
        }
    }

    public func playCue(forMuted isMuted: Bool) {
        guard SettingsStore.shared.audioFeedbackEnabled else { return }

        let soundName = isMuted ? SettingsStore.shared.muteSoundName : SettingsStore.shared.unmuteSoundName
        playSound(named: soundName)
    }

    public func playSound(named name: String) {
        soundQueue.async { [weak self] in
            guard let self = self else { return }

            if let sound = self.cachedSounds[name] {
                // Stop any current playback of this sound to avoid delay/overlap
                if sound.isPlaying {
                    sound.stop()
                }
                sound.play()
            } else if let sound = NSSound(named: NSSound.Name(name)) ?? NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true) {
                self.cachedSounds[name] = sound
                sound.play()
            } else {
                // Fallback to system alert sound
                NSSound.beep()
            }
        }
    }
}

import Foundation
import AVFoundation
import Combine

public final class MicTestManager: ObservableObject {
    public static let shared = MicTestManager()

    @Published public private(set) var isTesting: Bool = false
    @Published public private(set) var audioLevel: Float = 0.0 // 0.0 to 1.0
    @Published public var isHearMyselfEnabled: Bool = false {
        didSet {
            if isTesting {
                restartTesting()
            }
        }
    }

    private var audioEngine: AVAudioEngine?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Observe device changes so test follows the selected device
        AudioEngine.shared.$defaultDeviceID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.isTesting == true {
                    self?.restartTesting()
                }
            }
            .store(in: &cancellables)
    }

    public func toggleTesting() {
        if isTesting {
            stopTesting()
        } else {
            startTesting()
        }
    }

    public func startTesting() {
        guard !isTesting else { return }

        // Ensure microphone access
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            PermissionManager.shared.requestMicrophonePermission { [weak self] granted in
                if granted {
                    self?.beginAudioEngine()
                }
            }
        } else if status == .authorized {
            beginAudioEngine()
        } else {
            PermissionManager.shared.openSystemSettingsMicrophone()
        }
    }

    private func beginAudioEngine() {
        stopTesting()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        guard format.sampleRate > 0 && format.channelCount > 0 else {
            NSLog("[MicMute] Invalid audio input format.")
            return
        }

        // Install buffer tap for live volume meter
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameLength))
            let db = 20 * log10(max(rms, 0.0001))
            // Map -48dB ... -3dB to 0.0 ... 1.0
            let rawLevel = max(0.0, min(1.0, (db + 48.0) / 45.0))

            DispatchQueue.main.async {
                if rawLevel > self.audioLevel {
                    self.audioLevel = rawLevel
                } else {
                    self.audioLevel = max(0.0, self.audioLevel * 0.82 + rawLevel * 0.18)
                }
            }
        }

        // Audio passthrough (hear myself) if enabled
        if isHearMyselfEnabled {
            engine.connect(input, to: engine.mainMixerNode, format: format)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.isTesting = true
        } catch {
            NSLog("[MicMute] Failed to start AVAudioEngine: \(error.localizedDescription)")
            self.audioLevel = 0.0
            self.isTesting = false
        }
    }

    public func stopTesting() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.audioEngine = nil
        }
        self.isTesting = false
        self.audioLevel = 0.0
    }

    private func restartTesting() {
        stopTesting()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.beginAudioEngine()
        }
    }
}

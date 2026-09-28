import Foundation
import AVFoundation
import Combine

public final class MicTestManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    public static let shared = MicTestManager()

    // Recording State
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var audioLevel: Float = 0.0 // 0.0 to 1.0
    @Published public private(set) var recordingDuration: TimeInterval = 0.0
    @Published public private(set) var hasRecording: Bool = false

    // Playback State
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var playbackProgress: Double = 0.0
    @Published public private(set) var playbackTime: TimeInterval = 0.0
    @Published public private(set) var totalDuration: TimeInterval = 0.0

    private var audioEngine: AVAudioEngine?
    private var recordedAudioFile: AVAudioFile?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var recordingTimer: Timer?

    private let recordingURL: URL = {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("MicMute_TestClip.caf")
    }()

    private var cancellables = Set<AnyCancellable>()

    public override init() {
        super.init()

        // Re-check existing file
        if FileManager.default.fileExists(atPath: recordingURL.path) {
            if let player = try? AVAudioPlayer(contentsOf: recordingURL) {
                self.hasRecording = true
                self.totalDuration = player.duration
            }
        }

        // Stop if device changes
        AudioEngine.shared.$defaultDeviceID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.isRecording == true {
                    self?.stopRecording()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        stopRecording()
        stopPlayback()
    }

    // MARK: - Recording Actions

    public func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    public func startRecording() {
        guard !isRecording else { return }

        // Stop any active playback
        stopPlayback()

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            PermissionManager.shared.requestMicrophonePermission { [weak self] granted in
                if granted {
                    self?.beginRecordingEngine()
                }
            }
        } else if status == .authorized {
            beginRecordingEngine()
        } else {
            PermissionManager.shared.openSystemSettingsMicrophone()
        }
    }

    private func beginRecordingEngine() {
        // Clean up previous file
        try? FileManager.default.removeItem(at: recordingURL)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        guard format.sampleRate > 0 && format.channelCount > 0 else {
            NSLog("[MicMute] Invalid audio input format.")
            return
        }

        do {
            self.recordedAudioFile = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
        } catch {
            NSLog("[MicMute] Failed to create audio file: \(error.localizedDescription)")
            return
        }

        self.recordingDuration = 0.0

        // Install buffer tap: writes to file AND updates volume meter
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            // 1. Write buffer to recording file (never route to speakers to avoid feedback loops!)
            try? self.recordedAudioFile?.write(from: buffer)

            // 2. Compute RMS volume level for UI meter
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
            let rawLevel = max(0.0, min(1.0, (db + 48.0) / 45.0))

            DispatchQueue.main.async {
                if rawLevel > self.audioLevel {
                    self.audioLevel = rawLevel
                } else {
                    self.audioLevel = max(0.0, self.audioLevel * 0.82 + rawLevel * 0.18)
                }
            }
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.isRecording = true
            self.hasRecording = false

            // Track duration
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.recordingDuration += 0.1
            }
        } catch {
            NSLog("[MicMute] Failed to start recording engine: \(error.localizedDescription)")
            self.audioLevel = 0.0
            self.isRecording = false
        }
    }

    public func stopRecording() {
        guard isRecording else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.audioEngine = nil
        }

        self.recordedAudioFile = nil
        self.isRecording = false
        self.audioLevel = 0.0

        // Check file created
        if FileManager.default.fileExists(atPath: recordingURL.path) {
            if let player = try? AVAudioPlayer(contentsOf: recordingURL) {
                self.totalDuration = player.duration
                self.hasRecording = player.duration > 0.1
            }
        }
    }

    // MARK: - Playback Actions

    public func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            playRecording()
        }
    }

    public func playRecording() {
        guard hasRecording else { return }

        // If player is not initialized or finished, create it
        if audioPlayer == nil {
            do {
                let player = try AVAudioPlayer(contentsOf: recordingURL)
                player.delegate = self
                player.prepareToPlay()
                self.audioPlayer = player
                self.totalDuration = player.duration
            } catch {
                NSLog("[MicMute] Failed to initialize playback player: \(error.localizedDescription)")
                return
            }
        }

        guard let player = audioPlayer else { return }

        // If was at the end, restart from beginning
        if player.currentTime >= player.duration - 0.05 {
            player.currentTime = 0
        }

        player.play()
        self.isPlaying = true

        startPlaybackTimer()
    }

    public func pausePlayback() {
        audioPlayer?.pause()
        self.isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    public func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        self.audioPlayer = nil
        self.isPlaying = false
        self.playbackProgress = 0.0
        self.playbackTime = 0.0
    }

    public func seek(to progress: Double) {
        guard let player = audioPlayer ?? (try? AVAudioPlayer(contentsOf: recordingURL)) else { return }
        let clamped = max(0.0, min(1.0, progress))
        let targetTime = clamped * player.duration
        player.currentTime = targetTime
        self.playbackTime = targetTime
        self.playbackProgress = clamped
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            if player.duration > 0 {
                self.playbackTime = player.currentTime
                self.playbackProgress = player.currentTime / player.duration
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playbackTimer?.invalidate()
        playbackTimer = nil
        self.isPlaying = false
        self.playbackProgress = 1.0
        self.playbackTime = totalDuration

        // Reset to 0 after short delay so user can click play again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, !self.isPlaying else { return }
            self.playbackProgress = 0.0
            self.playbackTime = 0.0
            self.audioPlayer?.currentTime = 0
        }
    }
}

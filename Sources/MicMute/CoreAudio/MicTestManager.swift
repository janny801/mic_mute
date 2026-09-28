import Foundation
import AVFoundation
import Combine

public final class MicTestManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    public static let shared = MicTestManager()

    // Live Monitoring State
    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var liveAudioLevel: Float = 0.0 // 0.0 to 1.0

    // Recording State
    @Published public private(set) var isRecordingClip: Bool = false
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
    private var liveMonitoringTimeoutTimer: Timer?

    @Published public private(set) var isManualMonitoringActive: Bool = false

    private let recordingURL: URL = {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("MicMute_TestClip.caf")
    }()

    private var cancellables = Set<AnyCancellable>()

    public override init() {
        super.init()

        // Check if an existing recording exists
        if FileManager.default.fileExists(atPath: recordingURL.path) {
            if let player = try? AVAudioPlayer(contentsOf: recordingURL) {
                self.hasRecording = player.duration > 0.1
                self.totalDuration = player.duration
            }
        }

        // Restart live monitoring when default device changes
        AudioEngine.shared.$defaultDeviceID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.isMonitoring == true {
                    self?.restartMonitoring()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        stopAll()
    }

    // MARK: - Live Monitoring

    public func toggleLiveMonitoring() {
        if isManualMonitoringActive {
            isManualMonitoringActive = false
            stopLiveMonitoring()
        } else {
            isManualMonitoringActive = true
            startLiveMonitoring()

            // Automatically stop after 60 seconds to release microphone and restore audio profiles
            liveMonitoringTimeoutTimer?.invalidate()
            liveMonitoringTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    if self?.isManualMonitoringActive == true && !(self?.isRecordingClip ?? false) {
                        self?.isManualMonitoringActive = false
                        self?.stopLiveMonitoring()
                    }
                }
            }
        }
    }

    public func startLiveMonitoring() {
        guard !isMonitoring else { return }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            PermissionManager.shared.requestMicrophonePermission { [weak self] granted in
                if granted {
                    self?.beginAudioEngine()
                }
            }
        } else if status == .authorized {
            beginAudioEngine()
        }
    }

    private func beginAudioEngine() {
        guard audioEngine == nil else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        guard format.sampleRate > 0 && format.channelCount > 0 else {
            NSLog("[MicMute] Invalid audio input format for monitoring.")
            return
        }

        // Tap for live volume meter (and optional recording writing)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            // 1. If currently recording a test clip, write buffer to file (never to speakers!)
            if self.isRecordingClip {
                try? self.recordedAudioFile?.write(from: buffer)
            }

            // 2. Compute live volume level
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
                // If system microphone is muted, force level to 0
                if AudioEngine.shared.isMuted {
                    self.liveAudioLevel = 0.0
                } else {
                    if rawLevel > self.liveAudioLevel {
                        self.liveAudioLevel = rawLevel
                    } else {
                        self.liveAudioLevel = max(0.0, self.liveAudioLevel * 0.82 + rawLevel * 0.18)
                    }
                }
            }
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.isMonitoring = true
        } catch {
            NSLog("[MicMute] Failed to start live monitoring engine: \(error.localizedDescription)")
            self.isMonitoring = false
            self.liveAudioLevel = 0.0
        }
    }

    public func stopLiveMonitoring() {
        liveMonitoringTimeoutTimer?.invalidate()
        liveMonitoringTimeoutTimer = nil
        isManualMonitoringActive = false

        if isRecordingClip {
            stopRecordingClip()
        }

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.audioEngine = nil
        }

        self.isMonitoring = false
        self.liveAudioLevel = 0.0
    }

    private func restartMonitoring() {
        guard isManualMonitoringActive || isRecordingClip else {
            stopLiveMonitoring()
            return
        }

        let wasRecording = isRecordingClip
        if wasRecording {
            stopRecordingClip()
        }
        stopLiveMonitoring()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, self.isManualMonitoringActive else { return }
            self.startLiveMonitoring()
        }
    }

    // MARK: - Recording Clip (Test Voice)

    public func startRecordingClip() {
        guard !isRecordingClip else { return }

        // Stop any active playback
        stopPlayback()

        // Ensure engine is running
        if !isMonitoring {
            startLiveMonitoring()
        }

        guard let engine = audioEngine else { return }
        let format = engine.inputNode.inputFormat(forBus: 0)

        try? FileManager.default.removeItem(at: recordingURL)

        do {
            self.recordedAudioFile = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
        } catch {
            NSLog("[MicMute] Failed to create test recording file: \(error.localizedDescription)")
            return
        }

        self.recordingDuration = 0.0
        self.isRecordingClip = true
        self.hasRecording = false

        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.recordingDuration += 0.1
        }
    }

    public func stopRecordingClip() {
        guard isRecordingClip else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil

        self.isRecordingClip = false
        self.recordedAudioFile = nil

        // If manual live monitoring was not requested, immediately shut down engine to release microphone
        if !isManualMonitoringActive {
            stopLiveMonitoring()
        }

        // Verify recorded file
        if FileManager.default.fileExists(atPath: recordingURL.path) {
            if let player = try? AVAudioPlayer(contentsOf: recordingURL) {
                self.totalDuration = player.duration
                self.hasRecording = player.duration > 0.1
                self.audioPlayer = player
                player.delegate = self
                player.prepareToPlay()
            }
        }
    }

    public func deleteRecording() {
        stopPlayback()
        try? FileManager.default.removeItem(at: recordingURL)
        self.hasRecording = false
        self.totalDuration = 0.0
        self.playbackProgress = 0.0
        self.playbackTime = 0.0
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, !self.isPlaying else { return }
            self.playbackProgress = 0.0
            self.playbackTime = 0.0
            self.audioPlayer?.currentTime = 0
        }
    }

    public func stopAll() {
        liveMonitoringTimeoutTimer?.invalidate()
        liveMonitoringTimeoutTimer = nil
        isManualMonitoringActive = false
        stopRecordingClip()
        stopPlayback()
        stopLiveMonitoring()
    }
}

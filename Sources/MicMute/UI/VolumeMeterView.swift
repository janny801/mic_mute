import SwiftUI

public struct VolumeMeterView: View {
    @ObservedObject var micTest = MicTestManager.shared
    @ObservedObject var audioEngine = AudioEngine.shared

    private let segmentCount = 18

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Continuous Live VU Level Meter Bar
            HStack(spacing: 3) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    let threshold = Float(index) / Float(segmentCount)
                    let isActive = !audioEngine.isMuted && micTest.liveAudioLevel >= threshold

                    RoundedRectangle(cornerRadius: 2)
                        .fill(segmentColor(for: index, isActive: isActive))
                        .frame(height: 14)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // 2. Status & Options Row
            HStack(spacing: 12) {
                // Live Input Status Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(audioEngine.isMuted ? .red : (micTest.liveAudioLevel > 0.05 ? .green : .secondary))
                }

                Spacer()

                // Test Recording Option Button
                Button(action: {
                    if micTest.isRecordingClip {
                        micTest.stopRecordingClip()
                    } else {
                        micTest.startRecordingClip()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: micTest.isRecordingClip ? "stop.fill" : (micTest.hasRecording ? "arrow.clockwise" : "record.circle"))
                        Text(micTest.isRecordingClip ? "Stop Test" : (micTest.hasRecording ? "Re-record" : "Record Test Clip"))
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(micTest.isRecordingClip ? .red : (micTest.hasRecording ? .secondary : .accentColor))
            }

            // 3. Active Recording Badge
            if micTest.isRecordingClip {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Recording: \(formatTime(micTest.recordingDuration))")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.red)

                    Text("— Speak to record sample without feedback echo")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.08)))
            }

            // 4. Playback Controls Player (Appears when a test clip exists)
            if micTest.hasRecording && !micTest.isRecordingClip {
                HStack(spacing: 12) {
                    // Play / Pause
                    Button(action: {
                        micTest.togglePlayback()
                    }) {
                        Image(systemName: micTest.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(micTest.isPlaying ? "Pause Playback" : "Play Recorded Mic Test")

                    // Scrubber
                    Slider(
                        value: Binding(
                            get: { micTest.playbackProgress },
                            set: { micTest.seek(to: $0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.small)

                    // Timestamp
                    Text("\(formatTime(micTest.playbackTime)) / \(formatTime(micTest.totalDuration))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 70, alignment: .trailing)

                    // Delete / Clear button
                    Button(action: {
                        micTest.deleteRecording()
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Test Recording")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }

    private var statusDotColor: Color {
        if audioEngine.isMuted {
            return .red
        } else if micTest.liveAudioLevel > 0.05 {
            return .green
        } else {
            return .secondary
        }
    }

    private var statusText: String {
        if audioEngine.isMuted {
            return "Microphone Muted"
        } else if micTest.liveAudioLevel > 0.65 {
            return "Strong Signal (Peak)"
        } else if micTest.liveAudioLevel > 0.05 {
            return "Voice Detected"
        } else {
            return "Live Meter Ready (Speak to test)"
        }
    }

    private func segmentColor(for index: Int, isActive: Bool) -> Color {
        guard isActive else {
            return Color.secondary.opacity(0.15)
        }

        let ratio = Double(index) / Double(segmentCount)
        if ratio < 0.65 {
            return Color.green
        } else if ratio < 0.85 {
            return Color.yellow
        } else {
            return Color.red
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
